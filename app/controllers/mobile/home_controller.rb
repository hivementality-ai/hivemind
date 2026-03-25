# frozen_string_literal: true

module Mobile
  class HomeController < BaseController
    def index
      @recent_sessions = Session.includes(:agent)
                                .where(status: :active)
                                .order(last_activity_at: :desc)
                                .limit(10)
      @agents = Agent.enabled.order(:name)
    end
  end
end
