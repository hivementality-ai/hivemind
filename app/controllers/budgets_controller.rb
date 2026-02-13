# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :authenticate_user!

  def index
    @agents = Agent.visible.includes(:agent_budgets, :usage_records).order(:name)
  end

  def update
    agent = Agent.find(params[:agent_id])

    %w[daily monthly].each do |period|
      limit_key = "#{period}_limit"
      next unless params[limit_key].present?

      dollars = params[limit_key].to_f
      cents = (dollars * 100).to_i

      budget = agent.agent_budgets.find_or_initialize_by(period: period)
      budget.update!(limit_cents: cents)
    end

    redirect_to budgets_path, notice: "Budget updated for #{agent.name}"
  end
end
