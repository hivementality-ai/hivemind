# frozen_string_literal: true

class ApiIntegrationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_integration, only: %i[show edit update destroy test]

  def index
    @integrations = ApiIntegration.order(:name)
  end

  def new
    @integration = ApiIntegration.new
  end

  def create
    spec_input = parse_spec_input

    if spec_input
      result = ApiIntegrations::SpecParser.call(spec_input: spec_input)

      if result.success?
        data = result.data
        @integration = ApiIntegration.new(
          name: params[:api_integration][:name].presence || data[:title] || "Unnamed API",
          base_url: params[:api_integration][:base_url].presence || data[:base_url],
          description: data[:description],
          spec_format: data[:spec_format],
          spec_data: data[:spec_data],
          endpoints: data[:endpoints],
          auth_config: build_auth_config,
          default_headers: parse_json_field(:default_headers),
          user: current_user
        )
      else
        redirect_to new_api_integration_path, alert: result.error
        return
      end
    else
      @integration = ApiIntegration.new(integration_params.merge(user: current_user))
    end

    if @integration.save
      store_api_key if params[:api_key].present?
      redirect_to api_integration_path(@integration), notice: "API integration created with #{@integration.endpoints&.size || 0} endpoints."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def edit; end

  def update
    # Re-parse spec if new one uploaded
    spec_input = parse_spec_input
    if spec_input
      result = ApiIntegrations::SpecParser.call(spec_input: spec_input)
      if result.success?
        data = result.data
        @integration.assign_attributes(
          spec_format: data[:spec_format],
          spec_data: data[:spec_data],
          endpoints: data[:endpoints],
          description: data[:description].presence || @integration.description
        )
      end
    end

    @integration.assign_attributes(integration_params)
    @integration.auth_config = build_auth_config if params[:auth_type].present?

    if @integration.save
      store_api_key if params[:api_key].present?
      redirect_to api_integration_path(@integration), notice: "API integration updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    vault_key = @integration.auth_config["vault_key"] || "#{@integration.name.parameterize}_api_key"
    VaultEntry.find_by(namespace: "api_integrations", key: vault_key)&.destroy
    @integration.destroy!
    redirect_to api_integrations_path, notice: "API integration deleted."
  end

  def test
    # Make a simple GET to the base URL to verify connectivity
    uri = URI.parse(@integration.base_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10

    req = Net::HTTP::Head.new(uri)
    @integration.request_headers.each { |k, v| req[k] = v }

    response = http.request(req)
    render json: { status: "ok", code: response.code, message: "Connected (HTTP #{response.code})" }
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  # Import from URL (fetch remote spec)
  def import
    url = params[:spec_url].to_s.strip
    return redirect_to new_api_integration_path, alert: "URL is required" if url.blank?

    response = Net::HTTP.get_response(URI.parse(url))
    unless response.is_a?(Net::HTTPSuccess)
      return redirect_to new_api_integration_path, alert: "Failed to fetch spec: HTTP #{response.code}"
    end

    result = ApiIntegrations::SpecParser.call(spec_input: response.body)
    unless result.success?
      return redirect_to new_api_integration_path, alert: result.error
    end

    data = result.data
    @integration = ApiIntegration.new(
      name: data[:title] || "Imported API",
      base_url: data[:base_url],
      description: data[:description],
      spec_format: data[:spec_format],
      spec_data: data[:spec_data],
      endpoints: data[:endpoints],
      user: current_user
    )

    if @integration.save
      redirect_to api_integration_path(@integration), notice: "Imported #{@integration.endpoints&.size || 0} endpoints from spec."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_integration
    @integration = ApiIntegration.find(params[:id])
  end

  def integration_params
    params.require(:api_integration).permit(:name, :base_url, :description, :enabled, :timeout_seconds)
  end

  def build_auth_config
    auth_type = params[:auth_type].to_s
    config = { "type" => auth_type }

    case auth_type
    when "api_key"
      config["header_name"] = params[:auth_header_name].presence || "X-API-Key"
    when "bearer"
      # No extra config needed
    when "basic"
      config["username"] = params[:auth_username].to_s
    end

    name = params.dig(:api_integration, :name) || @integration&.name || "unnamed"
    config["vault_key"] = "#{name.to_s.parameterize}_api_key"
    config
  end

  def store_api_key
    vault_key = @integration.auth_config["vault_key"] || "#{@integration.name.parameterize}_api_key"
    entry = VaultEntry.find_or_initialize_by(namespace: "api_integrations", key: vault_key)
    entry.encrypted_value = params[:api_key]
    entry.save!
  end

  def parse_spec_input
    if params[:spec_file].present?
      params[:spec_file].read
    elsif params[:spec_text].present?
      params[:spec_text]
    end
  end

  def parse_json_field(field)
    raw = params[field].to_s.strip
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
