# frozen_string_literal: true

# Connector screens: list, add, edit, enable or disable, delete, and try an
# operation against the live API.
#
# Admin/owner only. A connector never holds a secret; its auth settings are
# "vault:namespace/key" references picked from existing vault entries.
class ConnectorsController < ApplicationController
  OUTPUT_PREVIEW_CHARS = 1_000
  AUTH_FIELDS = (Connector::PLAIN_AUTH_KEYS + Connector::REQUIRED_AUTH_KEYS.values.flatten +
                 Connector::OPTIONAL_AUTH_KEYS.values.flatten).uniq.freeze

  before_action :authorize_admin_or_owner!
  before_action :set_connector, only: %i[edit update destroy toggle_enabled try_operation export]

  def index
    @connectors = Connector.order(:name)
  end

  def new
    @connector = Connector.new(enabled: true, auth_scheme: "none")
    @operations_text = "[]"
  end

  def create
    @connector = Connector.new(created_by: current_user)
    if apply_and_save
      redirect_to connectors_path, notice: "Connector '#{@connector.name}' added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @operations_text = JSON.pretty_generate(@connector.operations)
  end

  def update
    if apply_and_save
      redirect_to connectors_path, notice: "Connector '#{@connector.name}' updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @connector.destroy!
    redirect_to connectors_path, notice: "Connector '#{@connector.name}' deleted."
  end

  def toggle_enabled
    @connector.update!(enabled: !@connector.enabled)
    redirect_to connectors_path, notice: "Connector '#{@connector.name}' #{@connector.enabled? ? 'enabled' : 'disabled'}."
  end

  # Downloads the connector as shareable JSON with every secret field left as a placeholder.
  def export
    send_data JSON.pretty_generate(Connectors::Exchange.export(@connector)),
              filename: "#{@connector.slug}.connector.json", type: "application/json", disposition: "attachment"
  end

  # Adds a shared connector as a new disabled one, so a person reviews it and fills in its keys first.
  def import
    connector = Connectors::Exchange.build(params[:connector_json])
    connector.created_by = current_user
    if connector.save
      redirect_to edit_connector_path(connector), notice: "Imported '#{connector.name}'. It is disabled until you point its keys at your vault and turn it on."
    else
      redirect_to connectors_path, alert: "Could not import: #{connector.errors.full_messages.to_sentence}"
    end
  rescue Connectors::Exchange::Error => e
    redirect_to connectors_path, alert: "Could not import: #{e.message}"
  end

  # Runs one operation for real and shows the status and the start of the output on the edit page.
  def try_operation
    @operations_text = JSON.pretty_generate(@connector.operations)
    @try = run_operation(params[:operation].to_s, params[:input].to_s)
    render :edit
  end

  private

  def set_connector
    @connector = Connector.find(params[:id])
  end

  def connector_params
    params.require(:connector).permit(:name, :slug, :description, :base_url, :auth_scheme, :enabled)
  end

  def apply_and_save
    @connector.assign_attributes(connector_params)
    @connector.slug = @connector.name.to_s.parameterize(separator: "_") if @connector.slug.blank?
    @connector.auth_config = auth_config_from_params
    @operations_text = params.dig(:connector, :operations_json).to_s
    operations_error = assign_operations
    @connector.valid?
    @connector.errors.add(:operations, operations_error) if operations_error
    @connector.errors.empty? && @connector.save
  end

  # Keeps only the auth fields the chosen scheme uses, so a stale field from a
  # different scheme can't fail validation.
  def auth_config_from_params
    fields = params.dig(:connector, :auth)&.permit(*AUTH_FIELDS)&.to_h || {}
    scheme = @connector.auth_scheme.to_s
    allowed = Connector::REQUIRED_AUTH_KEYS.fetch(scheme, []) + Connector::OPTIONAL_AUTH_KEYS.fetch(scheme, [])
    fields.slice(*allowed).compact_blank
  end

  # @return [String, nil] an error message when the JSON can't be read
  def assign_operations
    parsed = JSON.parse(@operations_text.presence || "[]")
    @connector.operations = parsed
    nil
  rescue JSON::ParserError
    "must be valid JSON"
  end

  def run_operation(name, input_text)
    params_hash = JSON.parse(input_text.presence || "{}")
    return { operation: name, error: "Inputs must be a JSON object, like {\"id\": \"42\"}" } unless params_hash.is_a?(Hash)

    result = Connectors::Executor.call(connector: @connector, operation: name, params: params_hash)
    return { operation: name, error: result.error } unless result.success?

    output = result.data[:output].to_s
    { operation: name, status: result.data[:status], output: output.truncate(OUTPUT_PREVIEW_CHARS),
      more: output.length > OUTPUT_PREVIEW_CHARS || result.data[:truncated] }
  rescue JSON::ParserError
    { operation: name, error: "Inputs are not valid JSON" }
  end
end
