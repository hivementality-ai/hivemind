# frozen_string_literal: true

class ResearchSessionsController < ApplicationController
  before_action :authenticate_user!

  def index
    @research_sessions = ResearchSession.includes(:agent)
                                        .order(created_at: :desc)
                                        .limit(100)
  end

  def show
    @research_session = ResearchSession.find(params[:id])
  end
end
