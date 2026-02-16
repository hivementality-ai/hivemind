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

    @usage_today = calculate_usage_today
    @memories = MemoryEntry.where(agent: @agent).order(created_at: :desc).limit(20)
  end

  def new
    @agent = Agent.new
    @teams = Team.order(:name)
  end

  def create
    @agent = Agent.new(agent_params)

    if @agent.save
      sync_skill_tools(@agent)
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
    if @agent.update(agent_params)
      sync_skill_tools(@agent, removed_skill_ids: old_skill_ids - @agent.skill_ids)
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
    @agent = Agent.find(params[:id])
  end

  # When skills are assigned, auto-add their required tools.
  # When skills are removed, remove tools that were only there because of that skill.
  def sync_skill_tools(agent, removed_skill_ids: [])
    # Add tools required by newly assigned skills
    agent.skills.includes(:tools).each do |skill|
      skill.tools.each do |tool|
        AgentTool.find_or_create_by(agent: agent, tool: tool)
      end
    end

    # Remove tools from removed skills (only if no other assigned skill still needs them)
    if removed_skill_ids.any?
      removed_skills = Skill.where(id: removed_skill_ids).includes(:tools)
      remaining_tool_ids = agent.skills.flat_map { |s| s.tool_ids }.uniq

      removed_skills.each do |skill|
        skill.tools.each do |tool|
          next if remaining_tool_ids.include?(tool.id)

          AgentTool.where(agent: agent, tool: tool).destroy_all
        end
      end
    end
  end

  def agent_params
    params.require(:agent).permit(
      :name, :role, :team_id, :model_provider, :llm_model,
      :daily_budget_limit, :monthly_budget_limit, :workspace_path,
      :system_prompt, :custom_instructions, :enabled,
      :thinking_enabled, :thinking_budget_tokens, :thinking_visibility,
      tool_ids: [],
      skill_ids: []
    )
  end

  def calculate_usage_today
    today_start = Time.current.beginning_of_day

    usage = UsageRecord.where(agent_id: @agent.id)
                      .where("created_at >= ?", today_start)

    {
      total_cost: usage.sum(:cost_cents),
      total_tokens: usage.sum("input_tokens + output_tokens"),
      request_count: usage.count
    }
  end
end
