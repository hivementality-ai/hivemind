# frozen_string_literal: true

class AgentsController < ApplicationController
  before_action :set_agent, only: [ :show, :edit, :update, :destroy ]

  def index
    @agents = Agent.visible.includes(:team).order(:name)
  end

  def show
    @recent_sessions = @agent.sessions
                             .order(created_at: :desc)
                             .limit(10)

    @pending_approvals = ApprovalRequest.where(agent_id: @agent.id)
                                       .pending
                                       .not_expired
                                       .order(requested_at: :desc)

    @usage_today = @agent.usage_today
    @memories = MemoryEntry.where(agent: @agent).order(created_at: :desc).limit(20)
  end

  def new
    @agent = Agent.new
    @teams = Team.order(:name)
  end

  def create
    @agent = Agent.new(agent_params)
    assign_restricted_attrs(@agent)

    if @agent.save
      Agents::SyncSkillTools.call(agent: @agent)
      redirect_to @agent, notice: "Agent created successfully"
    else
      @teams = Team.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @teams = Team.order(:name)
  end

  def update
    old_skill_ids = @agent.skill_ids.dup
    @agent.assign_attributes(agent_params)
    assign_restricted_attrs(@agent)
    if @agent.save
      Agents::SyncSkillTools.call(agent: @agent, removed_skill_ids: old_skill_ids - @agent.skill_ids)
      redirect_to @agent, notice: "Agent updated successfully"
    else
      @teams = Team.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @agent.destroy
    redirect_to agents_url, notice: "Agent deleted successfully"
  end

  private

  def set_agent
    @agent = Agent.find_by_slug(params[:slug])
    render file: "public/404.html", status: :not_found unless @agent
  end

  def agent_params
    params.require(:agent).permit(
      :name, :team_id, :model_provider, :llm_model,
      :daily_budget_limit, :monthly_budget_limit, :workspace_path,
      :system_prompt, :custom_instructions, :enabled, :avatar,
      :thinking_enabled, :thinking_budget_tokens, :thinking_visibility,
      tool_ids: [],
      skill_ids: []
    )
  end

  MODEL_CONFIG_FIELDS = %w[context_window max_output_tokens temperature top_p top_k repeat_penalty].freeze

  def assign_restricted_attrs(agent)
    ap = params[:agent]
    return unless ap

    agent.role = ap[:role] if ap.key?(:role)
    agent.egress_policy_mode = ap[:egress_policy_mode] if ap.key?(:egress_policy_mode)
    agent.egress_policy_rules = ap[:egress_policy_rules] if ap.key?(:egress_policy_rules)
    agent.egress_policy_log_blocked = ap[:egress_policy_log_blocked] if ap.key?(:egress_policy_log_blocked)
    assign_model_config(agent)
  end

  def assign_model_config(agent)
    mc = agent.model_config || {}
    MODEL_CONFIG_FIELDS.each do |field|
      val = params[:agent][field]
      if val.present?
        mc[field] = val.to_f
        mc[field] = mc[field].to_i if %w[context_window max_output_tokens top_k].include?(field)
      else
        mc.delete(field)
      end
    end
    agent.model_config = mc
  end
end
