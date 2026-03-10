# frozen_string_literal: true

class TeamChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: [ :create ]
  before_action :set_session, only: [ :show, :message, :update, :interrupt ]

  # GET /team_chats — list all team chat sessions
  def index; end

  # POST /teams/:team_id/chats — create a new team chat session
  def create
    @chat_session = TeamChatSession.create!(
      team: @team,
      user: current_user,
      title: "#{@team.name} Chat"
    )

    redirect_to team_chat_path(@chat_session)
  end

  # PATCH /team_chats/:id — rename a team chat session
  def update
    new_title = params[:title].to_s.strip

    if new_title.blank? || new_title.length > 100
      render json: { error: "Title must be between 1 and 100 characters" }, status: :unprocessable_entity
      return
    end

    @session.update!(title: new_title)
    ActionCable.server.broadcast("team_chat_#{@session.id}", { type: "title_update", title: new_title })
    render json: { title: new_title }
  end

  # GET /team_chats/:id — show team chat interface
  def show
    @team = @session.team
    @agents = @team.agents.enabled.order(:name)
    @messages = @session.recent_messages(limit: 100)
    @past_sessions = @team.team_chat_sessions.recent.limit(20)
  end

  # POST /team_chats/:id/message — send a message to the team
  def message
    user_message = params[:message]&.strip
    has_attachments = params[:images].present? || params[:files].present?

    if user_message.blank? && !has_attachments
      head :unprocessable_entity
      return
    end

    result = TeamChats::SendMessage.call(
      session: @session,
      user: current_user,
      message: user_message,
      images: params[:images],
      files: params[:files]
    )

    if result.success?
      head :ok
    else
      head :unprocessable_entity
    end
  end

  # POST /team_chats/:id/interrupt — cancel, redirect, or inject into active agents
  def interrupt
    signal_type = params[:type].to_s.strip
    message = params[:message].to_s.strip

    unless SessionSignal::TYPES.include?(signal_type)
      render json: { error: "Invalid signal type. Must be: #{SessionSignal::TYPES.join(', ')}" }, status: :unprocessable_entity
      return
    end

    if signal_type != "cancel" && message.blank?
      render json: { error: "Message required for #{signal_type}" }, status: :unprocessable_entity
      return
    end

    # Fan out signal to all active agent sessions within this team chat
    agent_sessions = @session.agent_sessions.to_a
    agent_sessions.each do |agent_session|
      SessionSignal.set(agent_session.id, type: signal_type, message: message.presence)
    end

    # Broadcast immediately for visual feedback
    ActionCable.server.broadcast(
      "team_chat_#{@session.id}",
      { type: "interrupt_sent", signal_type: signal_type, message: message.presence }
    )

    render json: { status: "signal_sent", type: signal_type }
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_session
    @session = TeamChatSession.find(params[:id])
  end
end
