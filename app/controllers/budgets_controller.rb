# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_agent, only: [:edit, :update]
  
  def index
    @agents = Agent.includes(:agent_budgets).all
    @period_type = params[:period] || "daily"
  end
  
  def edit
    @budget = @agent.agent_budgets.find_or_initialize_by(period: params[:period_type] || "daily")
  end
  
  def update
    @budget = @agent.agent_budgets.find_or_initialize_by(period: params[:period_type])
    
    # Convert dollars to cents
    if params[:agent_budget][:limit_cents].present?
      params[:agent_budget][:limit_cents] = (params[:agent_budget][:limit_cents].to_f * 100).to_i
    end
    
    if @budget.update(budget_params)
      Audit::Log.call(
        actor: current_user.email,
        action: "budget.updated",
        resource: @agent,
        metadata: {
          period: @budget.period,
          limit_cents: @budget.limit_cents
        }
      )
      
      redirect_to budgets_path, notice: "Budget updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_agent
    @agent = Agent.find(params[:agent_id])
  end
  
  def budget_params
    params.require(:agent_budget).permit(:limit_cents, :period)
  end
end
