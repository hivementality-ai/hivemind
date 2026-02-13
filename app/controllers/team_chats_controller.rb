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
    has_attachments = params[:images].present? || params[:files].present?
    head(:unprocessable_entity) and return if user_message.blank? && !has_attachments

    team = @session.team

    # Parse @mentions to determine target
    mentions = TeamChatMessage.extract_mentions(user_message.to_s, team)
    target_agent = mentions[:agents].first if mentions[:agents].size == 1 && !mentions[:broadcast]

    # Save user message
    msg = @session.team_chat_messages.create!(
      sender_type: "user",
      sender_id: current_user.id,
      target_agent_id: target_agent&.id,
      content: user_message.to_s.presence || "[image]"
    )

    # Attach images
    [params[:images], params[:files]].compact.each do |file_list|
      Array(file_list).each do |upload|
        next unless upload.respond_to?(:content_type)
        if upload.content_type.start_with?("image/")
          msg.images.attach(upload)
        else
          msg.documents.attach(upload)
        end
      end
    end

    @session.touch

    # Build image URLs for broadcast
    image_urls = msg.images.map do |img|
      { url: Rails.application.routes.url_helpers.rails_blob_path(img, only_path: true), filename: img.filename.to_s }
    end

    # Build file info for broadcast
    file_info = msg.documents.attached? ? msg.documents.map { |d| { filename: d.filename.to_s, byte_size: d.byte_size } } : []

    # Broadcast user message to the room
    ActionCable.server.broadcast("team_chat_#{@session.id}", {
      type: "user_message",
      content: user_message.to_s,
      target_agent_id: target_agent&.id,
      target_agent_name: target_agent&.name,
      message_id: msg.id,
      images: image_urls.presence,
      files: file_info.presence
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
