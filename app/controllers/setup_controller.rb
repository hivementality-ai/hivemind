# frozen_string_literal: true

class SetupController < ApplicationController
  layout "setup"
  skip_before_action :authenticate_user!, only: [ :index, :account, :create_account, :ollama_models ]
  skip_before_action :verify_authenticity_token, only: [ :ollama_models ]
  before_action :redirect_if_setup_complete, except: [ :complete, :ollama_models ]
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

    provider_params.each do |provider, config|
      next if config[:api_key].blank?

      # Create or update the provider config
      pc = ProviderConfig.find_or_initialize_by(name: provider)
      pc.adapter_type = provider
      pc.enabled = true
      pc.vault_key = "providers/#{provider}_api_key"

      # Save selected models and default
      selected_models = config[:models] || []
      default_model = config[:default_model]
      pc.model_definitions = selected_models.map do |model_id|
        { "id" => model_id, "default" => (model_id == default_model) }
      end

      if pc.save
        # Store the key in vault
        VaultEntry.find_or_initialize_by(namespace: "providers", key: "#{provider}_api_key").tap do |ve|
          ve.encrypted_value = config[:api_key]
          errors << ve.errors.full_messages unless ve.save
        end

        # Store default model in settings
        Setting.set("default_model_#{provider}", default_model) if default_model.present?
      else
        errors << pc.errors.full_messages
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

  # Check Ollama connectivity and fetch available models
  def ollama_models
    url = params[:url].presence || "http://host.docker.internal:11434"

    # Validate URL to prevent SSRF
    uri = URI.parse("#{url}/api/tags")
    unless uri.is_a?(URI::HTTP) && uri.host.present? && !uri.host.match?(/\A\[?::1?\]?\z/) # allow local but block obvious abuse
      return render json: { status: "error", message: "Invalid Ollama URL" }, status: :unprocessable_entity
    end

    http = Net::HTTP.new(uri.host, uri.port) # rubocop:disable Brakeman/FileAccess
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 3
    http.read_timeout = 3

    response = http.request(Net::HTTP::Get.new(uri))
    data = JSON.parse(response.body)

    models = (data["models"] || []).map do |m|
      {
        id: m["name"],
        name: m["name"],
        size: (m["size"].to_f / 1_000_000_000).round(1),
        parameter_size: m.dig("details", "parameter_size"),
        family: m.dig("details", "family")
      }
    end.sort_by { |m| m[:name] }

    render json: { status: "connected", models: models }
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  # Done!
  def complete
    @agent = Agent.last
    @team = @agent&.team
  end

  private

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
      ollama: [ :api_key, :default_model, models: [] ]
    )
  end

  def team_params
    params.require(:team).permit(:name, :description, :custom_soul)
  end

  def agent_params
    params.require(:agent).permit(:name, :template_id, :team_id)
  end
end
