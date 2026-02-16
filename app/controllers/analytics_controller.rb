# frozen_string_literal: true

class AnalyticsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_period

  def index
    response = Analytics::TeamSummary.call(period: @period)

    if response.success?
      @summary = response.data[:summary]
      @per_agent = response.data[:per_agent]
      @agents = response.data[:agents]
    else
      flash.now[:alert] = response.error
      @summary = {}
      @per_agent = []
      @agents = []
    end
  end

  def show
    @agent = Agent.find_by_slug(params[:id])
    return render file: "public/404.html", status: :not_found unless @agent
    response = Analytics::AgentSummary.call(agent: @agent, period: @period)

    if response.success?
      @analytics = response.data
    else
      flash.now[:alert] = response.error
      @analytics = {}
    end
  end

  private

  def set_period
    @period = params[:period] || "week"
  end
end
