# frozen_string_literal: true

class SetupController < ApplicationController
  layout "setup"
  skip_before_action :authenticate_user!, only: [ :index, :account, :create_account, :ollama_models, :openai_compatible_models ]
  skip_before_action :verify_authenticity_token, only: [ :ollama_models, :openai_compatible_models ]
  before_action :redirect_if_setup_complete, except: [ :complete, :ollama_models, :openai_compatible_models ]
  before_action :authenticate_user!, only: [ :provider, :save_provider, :team, :save_team, :agent, :save_agent, :complete ]

  # Step 0: Landing — shows the welcome screen
  def index
    redirect_to setup_account_path
  end

  # Step 1: Create account
  def account
    redirect_to setup_provider_path if user_signed_in?
    @user = User.new
  end

  def create_account
    @user = User.new(account_params.merge(role: :owner))

    if @user.save
      sign_in(@user)
      redirect_to setup_provider_path
    else
      render :account, status: :unprocessable_entity
    end
  end

  # Step 2: Add at least one AI provider key
  def provider
    @provider_configs = ProviderConfig.all
  end

  def save_provider
    errors = []

    # Guard against missing providers key — submitting only an embedding provider
    # (no chat providers) must not raise ActionController::ParameterMissing.
    if params[:providers].present?
      provider_params.each do |provider, config|
        # Cloud providers (anthropic, openai) require an API key.
        # Toggle-based providers (ollama, openai_compatible) use the enabled flag;
        # API key is optional (e.g. local servers don't need one, but Minimax does).
        toggle_provider = %w[ollama openai_compatible].include?(provider)
        next if toggle_provider ? config[:enabled].blank? : config[:api_key].blank?

        # Create or update the provider config
        pc = ProviderConfig.find_or_initialize_by(name: provider)
        pc.adapter_type = provider
        pc.enabled = true
        pc.vault_key = "providers/#{provider}_api_key"
        pc.base_url = config[:base_url].presence if config.key?(:base_url)

        # Save selected models and default
        selected_models = config[:models] || []
        default_model = config[:default_model]
        pc.model_definitions = selected_models.map do |model_id|
          { "id" => model_id, "default" => (model_id == default_model) }
        end

        if pc.save
          # Store the key in vault (only if an actual API key was provided)
          if config[:api_key].present?
            VaultEntry.find_or_initialize_by(namespace: "providers", key: "#{provider}_api_key").tap do |ve|
              ve.encrypted_value = config[:api_key]
              errors << ve.errors.full_messages unless ve.save
            end
          end

          # Store default model in settings
          Setting.set("default_model_#{provider}", default_model) if default_model.present?
        else
          errors << pc.errors.full_messages
        end
      end
    end

    # Save embedding provider selection
    embedding_provider = params[:embedding_provider].presence || "ollama"
    if Embeddings::Registry::ADAPTERS.key?(embedding_provider)
      Setting.set("memory_embeddings_provider", embedding_provider)

      # Store Gemini embedding API key if provided
      if embedding_provider == "gemini" && params[:gemini_embedding_api_key].present?
        VaultEntry.find_or_initialize_by(namespace: "embedding", key: "google_ai_api_key").tap do |ve|
          ve.encrypted_value = params[:gemini_embedding_api_key]
          ve.save
        end
      end

      # Persist a custom Ollama base_url for embeddings even when the Ollama
      # chat provider isn't toggled on (e.g. remote-only embedding use-case).
      # Note: we do NOT set enabled: true here — this record is for URL storage
      # only and must not appear in ProviderConfig.enabled_providers, which gates
      # the chat provider setup step and populates the agent model dropdown.
      if embedding_provider == "ollama"
        ollama_base_url = params[:ollama_embedding_base_url].presence
        if ollama_base_url
          pc = ProviderConfig.find_or_initialize_by(adapter_type: "ollama")
          pc.name ||= "ollama"
          pc.vault_key ||= "providers/ollama_api_key"
          pc.base_url = ollama_base_url
          # For new records, ProviderConfig#set_defaults would set enabled: true via
          # after_initialize. Explicitly disable so an embedding-only config doesn't
          # appear in ProviderConfig.enabled_providers and bypass the chat provider gate.
          # Existing records that are already enabled (Ollama also used as chat provider)
          # keep their enabled status unchanged.
          pc.enabled = false if pc.new_record?
          pc.save
        end
      end
    end

    if ProviderConfig.enabled_providers.any?
      redirect_to setup_team_path
    else
      flash.now[:alert] = "Add at least one API key to continue."
      @provider_configs = ProviderConfig.all
      render :provider, status: :unprocessable_entity
    end
  end

  # Step 3: Create a team
  def team
    @team = Team.new
  end

  def save_team
    @team = Team.new(team_params)

    if @team.save
      redirect_to setup_agent_path(team_id: @team.id)
    else
      render :team, status: :unprocessable_entity
    end
  end

  # Step 4: Pick a template and deploy first agent
  def agent
    @team = Team.find(params[:team_id])
    @templates = AgentTemplate.where(featured: true).order(:name)
    @all_templates = AgentTemplate.order(:name)
  end

  def save_agent
    @team = Team.find(agent_params[:team_id])
    template = AgentTemplate.find(agent_params[:template_id])

    provider = ProviderConfig.enabled_providers.first
    model_config = template.model_config || {}

    @agent = Agent.new(
      name: agent_params[:name].presence || template.name,
      role: template.role,
      team: @team,
      system_prompt: template.system_prompt,
      llm_model: model_config["model"] || "claude-sonnet-4-5",
      model_provider: model_config["provider"] || provider&.adapter_type || "anthropic",
      tools_config: template.tools_config,
      enabled: true,
      status: :idle
    )

    if @agent.save
      # Mark setup as complete
      Setting.set("setup_complete", "true")
      redirect_to setup_complete_path
    else
      @templates = AgentTemplate.where(featured: true).order(:name)
      @all_templates = AgentTemplate.order(:name)
      render :agent, status: :unprocessable_entity
    end
  end

  def ollama_models
    render_remote_models(:ollama)
  end

  def openai_compatible_models
    render_remote_models(:openai_compatible)
  end

  # Done!
  def complete
    @agent = Agent.last
    @team = @agent&.team
  end

  private

  def render_remote_models(provider)
    result = Providers::FetchRemoteModels.call(provider, url: params[:url], api_key: params[:api_key])
    if result.success?
      render json: result.data
    else
      render json: { status: "error", message: result.error }, status: :unprocessable_entity
    end
  end

  def redirect_if_setup_complete
    redirect_to root_path if Setting.get("setup_complete") == "true"
  end

  def account_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end

  def provider_params
    params.require(:providers).permit(
      anthropic: [ :api_key, :default_model, models: [] ],
      openai: [ :api_key, :default_model, models: [] ],
      ollama: [ :api_key, :enabled, :default_model, :base_url, models: [] ],
      openai_compatible: [ :api_key, :enabled, :default_model, :base_url, models: [] ]
    )
  end

  def team_params
    params.require(:team).permit(:name, :description, :custom_soul)
  end

  def agent_params
    params.require(:agent).permit(:name, :template_id, :team_id)
  end
end
