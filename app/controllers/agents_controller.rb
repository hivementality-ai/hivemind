# frozen_string_literal: true

class AgentsController < ApplicationController
  before_action :set_agent, only: [:show, :edit, :update, :destroy]

  def index
    @agents = Agent.includes(:team).order(:name)
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
    if @agent.update(agent_params)
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

  def agent_params
    params.require(:agent).permit(
      :name, :role, :team_id, :model_provider, :llm_model,
      :daily_budget_limit, :monthly_budget_limit, :workspace_path,
      :system_prompt, :custom_instructions, :enabled
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
