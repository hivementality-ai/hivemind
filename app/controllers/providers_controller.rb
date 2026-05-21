# frozen_string_literal: true

class ProvidersController < ApplicationController
  before_action :authorize_admin_or_owner!
  before_action :load_provider, only: [ :show, :edit, :update ]

  # GET /providers
  # Admin interface to manage all provider credentials
  def index
    @providers = ProviderConfig.order(:name)
  end

  # GET /providers/:id
  # Show provider details (read-only for now, can be used for display)
  def show
  end

  # GET /providers/new
  # Show form to add a new provider
  def new
    @provider = ProviderConfig.new
    @available_types = %w[openai anthropic ollama openai_compatible]
  end

  # POST /providers
  # Create a new provider
  def create
    adapter_type = provider_params[:adapter_type]
    selected_models = provider_params[:models] || []
    default_model = provider_params[:default_model]

    custom_name = provider_params[:name].presence
    name = custom_name || (adapter_type == "openai_compatible" ? "OpenAI Compatible" : adapter_type.titleize)
    vault_slug = name.parameterize(separator: "_")
    vault_key = "providers/#{vault_slug}_api_key"

    model_definitions = selected_models.map do |model_id|
      { "id" => model_id, "default" => (model_id == default_model) }
    end

    custom_base_url = provider_params[:base_url].presence

    @provider = ProviderConfig.new(
      name: name,
      adapter_type: adapter_type,
      vault_key: vault_key,
      enabled: true,
      model_definitions: model_definitions,
      base_url: custom_base_url
    )

    if @provider.save
      if provider_params[:api_key].present?
        namespace, key = vault_key.split("/", 2)
        VaultEntry.find_or_initialize_by(namespace:, key:).tap do |ve|
          ve.encrypted_value = provider_params[:api_key]
          ve.save!
        end
      end

      Setting.set("default_model_#{adapter_type}", default_model) if default_model.present?

      redirect_to provider_path(@provider), notice: "Provider added successfully."
    else
      @available_types = %w[openai anthropic ollama openai_compatible]
      render :new, status: :unprocessable_entity
    end
  end

  # GET /providers/:id/edit
  # Show provider details with option to edit credentials
  def edit
    @available_models = available_models_for(@provider.adapter_type)
    @selected_models = @provider.model_definitions || []
    @api_key = @provider.api_key

    # If edit_mode=true, render the form view; otherwise render the show view
    render :edit_form if params[:edit_mode] == "true"
  end

  # PATCH/PUT /providers/:id
  # Update provider configuration
  def update
    # Build the model definitions from checkbox inputs
    selected_models = provider_params[:models] || []
    default_model = provider_params[:default_model]

    @provider.model_definitions = selected_models.map do |model_id|
      { "id" => model_id, "default" => (model_id == default_model) }
    end

    # Update base URL if provided (Ollama, OpenAI Compatible)
    @provider.base_url = provider_params[:base_url] if provider_params.key?(:base_url)

    # Save provider config
    if @provider.save
      # Update API key if provided
      if provider_params[:api_key].present?
        namespace, key = @provider.vault_key.split("/", 2)
        VaultEntry.find_or_initialize_by(namespace:, key:).tap do |ve|
          ve.encrypted_value = provider_params[:api_key]
          ve.save!
        end
      end

      # Save default model to settings if provided
      if default_model.present?
        Setting.set("default_model_#{@provider.adapter_type}", default_model)
      end

      # Anthropic-only debug toggles (always write both so unchecking
      # actually clears the flag — checkboxes don't post when unchecked,
      # but the hidden twin in the form posts "0" as a floor value).
      if @provider.adapter_type == "anthropic"
        Setting.set("prompt_debug_enabled", bool_param(provider_params[:prompt_debug_enabled]).to_s)
        Setting.set("anthropic_use_sdk_proxy", bool_param(provider_params[:anthropic_use_sdk_proxy]).to_s)
      end

      redirect_to provider_path(@provider), notice: "Provider updated successfully."
    else
      @available_models = available_models_for(@provider.adapter_type)
      @selected_models = @provider.model_definitions || []
      @api_key = @provider.api_key
      render :edit_form, status: :unprocessable_entity
    end
  end

  private

  def load_provider
    @provider = ProviderConfig.find(params[:id])
  end

  def provider_params
    permitted = [ :api_key, :default_model, :base_url, :prompt_debug_enabled, :anthropic_use_sdk_proxy, models: [] ]
    permitted.unshift(:adapter_type, :name) if action_name == "create"
    params.require(:provider_config).permit(*permitted)
  end

  def bool_param(val)
    %w[1 true on yes].include?(val.to_s.downcase)
  end

  def available_models_for(provider_type)
    case provider_type
    when "anthropic"
      [
        { id: "claude-opus-4-6", name: "Claude Opus 4.6", desc: "Most capable — complex reasoning & code" },
        { id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", desc: "Best balance of speed & intelligence" },
        { id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5", desc: "Previous generation — balanced speed & intelligence" },
        { id: "claude-haiku-4-5", name: "Claude Haiku 4.5", desc: "Fast & affordable for simple tasks" }
      ]
    when "openai"
      [
        { id: "gpt-5.4", name: "GPT-5.4", desc: "Latest flagship — complex reasoning & coding" },
        { id: "gpt-5.4-mini", name: "GPT-5.4 Mini", desc: "Fast & strong for high-volume workloads" },
        { id: "gpt-5.4-nano", name: "GPT-5.4 Nano", desc: "Cheapest — classification, extraction, sub-agents" },
        { id: "gpt-5.3-codex", name: "GPT-5.3 Codex", desc: "Best agentic coding model" },
        { id: "o3-pro", name: "o3-pro", desc: "Extended reasoning — hard problems, more compute" },
        { id: "o3", name: "o3", desc: "Advanced reasoning — math, science, code" },
        { id: "o4-mini", name: "o4-mini", desc: "Fast reasoning for complex problems" },
        { id: "gpt-5.2", name: "GPT-5.2", desc: "Previous flagship — coding & analysis" },
        { id: "gpt-4.1", name: "GPT-4.1", desc: "Great instruction following, 1M context" }
      ]
    when "ollama"
      # Ollama models should be dynamically fetched, but for now return empty
      # The edit view will handle dynamic loading via JavaScript
      []
    when "openai_compatible"
      # OpenAI Compatible models are dynamically fetched via JavaScript
      []
    else
      []
    end
  end
end
