# frozen_string_literal: true

module Mobile
  class AgentsController < BaseController
    def index
      @agents = Agent.enabled.order(:name)
    end

    def show
      @agent = Agent.by_slug(params[:slug]).first
      return redirect_to mobile_agents_path, alert: "Agent not found" unless @agent

      @recent_sessions = @agent.sessions.where(status: :active).order(last_activity_at: :desc).limit(5)
      @tools = @agent.tools
      @skills = @agent.skills
      @usage_today = @agent.usage_records.where("created_at >= ?", Time.current.beginning_of_day)
    end
  end
end
