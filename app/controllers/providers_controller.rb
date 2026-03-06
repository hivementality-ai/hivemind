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
    @existing_types = ProviderConfig.pluck(:adapter_type)
    @available_types = %w[openai anthropic ollama llama_cpp] - @existing_types

    if @available_types.empty?
      redirect_to providers_path, notice: "All provider types are already configured."
      return
    end
  end

  # POST /providers
  # Create a new provider
  def create
    adapter_type = provider_params[:adapter_type]
    selected_models = provider_params[:models] || []
    default_model = provider_params[:default_model]

    name = adapter_type == "llama_cpp" ? "llama.cpp" : adapter_type.titleize
    vault_key = "providers/#{adapter_type}_api_key"

    model_definitions = selected_models.map do |model_id|
      { "id" => model_id, "default" => (model_id == default_model) }
    end

    @provider = ProviderConfig.new(
      name: name,
      adapter_type: adapter_type,
      vault_key: vault_key,
      enabled: true,
      model_definitions: model_definitions
    )

    if @provider.save
      if provider_params[:api_key].present?
        VaultEntry.find_or_initialize_by(
          namespace: "providers",
          key: "#{adapter_type}_api_key"
        ).tap do |ve|
          ve.encrypted_value = provider_params[:api_key]
          ve.save!
        end
      end

      Setting.set("default_model_#{adapter_type}", default_model) if default_model.present?

      redirect_to provider_path(@provider), notice: "Provider added successfully."
    else
      @existing_types = ProviderConfig.pluck(:adapter_type)
      @available_types = %w[openai anthropic ollama llama_cpp] - @existing_types
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

    # Save provider config
    if @provider.save
      # Update API key if provided
      if provider_params[:api_key].present?
        VaultEntry.find_or_initialize_by(
          namespace: "providers",
          key: "#{@provider.adapter_type}_api_key"
        ).tap do |ve|
          ve.encrypted_value = provider_params[:api_key]
          ve.save!
        end
      end

      # Save default model to settings if provided
      if default_model.present?
        Setting.set("default_model_#{@provider.adapter_type}", default_model)
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

  def authorize_admin_or_owner!
    return if current_user.admin? || current_user.owner?

    redirect_to root_path, alert: "Access denied."
  end

  def provider_params
    permitted = [ :api_key, :default_model, models: [] ]
    permitted.unshift(:adapter_type) if action_name == "create"
    params.require(:provider_config).permit(*permitted)
  end

  def available_models_for(provider_type)
    case provider_type
    when "anthropic"
      [
        { id: "claude-opus-4-6", name: "Claude Opus 4.6", desc: "Most capable — complex reasoning & code" },
        { id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5", desc: "Best balance of speed & intelligence" },
        { id: "claude-haiku-4-5", name: "Claude Haiku 4.5", desc: "Fast & affordable for simple tasks" }
      ]
    when "openai"
      [
        { id: "gpt-5.2", name: "GPT-5.2", desc: "Latest flagship — great for coding & analysis" },
        { id: "gpt-5.2-mini", name: "GPT-5.2 Mini", desc: "Fast & cheap for everyday tasks" },
        { id: "gpt-5.2-nano", name: "GPT-5.2 Nano", desc: "Fastest & cheapest for simple tasks" },
        { id: "o3", name: "o3", desc: "Advanced reasoning — math, science, code" },
        { id: "o4-mini", name: "o4-mini", desc: "Fast reasoning for complex problems" }
      ]
    when "ollama"
      # Ollama models should be dynamically fetched, but for now return empty
      # The edit view will handle dynamic loading via JavaScript
      []
    when "llama_cpp"
      # llama.cpp models are dynamically fetched via JavaScript
      []
    else
      []
    end
  end
end
