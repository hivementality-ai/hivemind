# frozen_string_literal: true

class SessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_agent, only: [:create]
  before_action :set_session, only: [:show, :message]

  # GET /sessions — list all sessions
  def index
    @sessions = Session.includes(:agent)
                       .where(status: :active)
                       .order(last_activity_at: :desc)
                       .limit(50)
  end

  # POST /sessions — start a new chat with an agent
  def create
    @session = Session.create!(
      agent: @agent,
      session_key: SecureRandom.uuid,
      status: :active,
      transcript: [],
      metadata: { started_by: current_user.id },
      last_activity_at: Time.current
    )

    redirect_to session_path(@session)
  end

  # GET /sessions/:id — show chat interface
  def show
    @agent = @session.agent
    @messages = @session.transcript || []
  end

  # POST /sessions/:id/message — send a message (async via Sidekiq + ActionCable)
  def message
    user_message = params[:message]&.strip
    if user_message.blank?
      head :unprocessable_entity
      return
    end

    ChatStreamJob.perform_later(@session.id, user_message)
    head :ok
  end

  private

  def set_agent
    @agent = Agent.find(params[:agent_id])
  end

  def set_session
    @session = Session.find(params[:id])
  end
end
