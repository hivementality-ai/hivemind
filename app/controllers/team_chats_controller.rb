# frozen_string_literal: true

class TeamChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: [:create]
  before_action :set_session, only: [:show, :message]

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
    head(:unprocessable_entity) and return if user_message.blank?

    team = @session.team

    # Parse @mentions to determine target
    mentions = TeamChatMessage.extract_mentions(user_message, team)
    target_agent = mentions[:agents].first if mentions[:agents].size == 1 && !mentions[:broadcast]

    # Save user message
    msg = @session.team_chat_messages.create!(
      sender_type: "user",
      sender_id: current_user.id,
      target_agent_id: target_agent&.id,
      content: user_message
    )

    @session.touch

    # Broadcast user message to the room
    ActionCable.server.broadcast("team_chat_#{@session.id}", {
      type: "user_message",
      content: user_message,
      target_agent_id: target_agent&.id,
      target_agent_name: target_agent&.name,
      message_id: msg.id
    })

    # Trigger agent responses
    TeamChatJob.perform_later(@session.id, msg.id)

    head :ok
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_session
    @session = TeamChatSession.find(params[:id])
  end
end
