# frozen_string_literal: true

class TeamChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: [ :create ]
  before_action :set_session, only: [ :show, :message ]

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

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_session
    @session = TeamChatSession.find(params[:id])
  end
end
