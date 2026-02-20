# frozen_string_literal: true

class SessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_agent, only: [ :create ]
  before_action :set_session, only: [ :show, :message ]

  # GET /sessions — list all sessions
  def index
    @sessions = Session.includes(:agent)
                       .where(status: :active)
                       .order(last_activity_at: :desc)
                       .limit(50)

    # If agent_id is passed via GET, auto-create a session and redirect to chat
    if params[:agent_id].present? && request.get?
      agent = Agent.by_slug(params[:agent_id]).first || Agent.find_by(id: params[:agent_id])
      if agent
        session = Session.create!(
          agent: agent,
          session_key: SecureRandom.uuid,
          status: :active,
          transcript: [],
          metadata: { started_by: current_user.id },
          last_activity_at: Time.current
        )
        redirect_to session_path(session) and return
      end
    end
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
    @attachments = @session.chat_attachments.includes(file_attachment: :blob).index_by(&:message_index)
  end

  # POST /sessions/:id/message — send a message (async via Sidekiq + ActionCable)
  def message
    user_message = params[:message]&.strip
    has_attachments = params[:images].present? || params[:files].present?

    if user_message.blank? && !has_attachments
      head :unprocessable_entity
      return
    end

    # Check if there's a pending ask_user question
    if handle_pending_question(user_message)
      head :ok
      return
    end

    attachment_ids = process_attachments

    # Broadcast user message immediately for instant feedback
    broadcast_data = { type: "user_message", content: user_message }
    if attachment_ids.any?
      attachments = ChatAttachment.where(id: attachment_ids)
      broadcast_data[:images] = attachments.select { |a| a.content_type.start_with?('image/') }
                                           .map { |a| { id: a.id, filename: a.filename, url: rails_blob_url(a) } }
      broadcast_data[:files] = attachments.select { |a| !a.content_type.start_with?('image/') }
                                          .map { |a| { filename: a.filename, content_type: a.content_type, byte_size: a.byte_size } }
    end
    ActionCable.server.broadcast("session_#{@session.id}", broadcast_data)

    # Enqueue the actual processing job
    ChatStreamJob.perform_later(@session.id, user_message.to_s, attachment_ids)
    head :ok
  end

  private

  def handle_pending_question(user_message)
    redis_key = "ask_user_pending:#{@session.id}"
    cached_data = Rails.cache.read(redis_key)

    return false unless cached_data

    begin
      parsed_data = JSON.parse(cached_data)

      # Check if question hasn't timed out
      timeout_at = Time.parse(parsed_data["timeout_at"])
      if Time.current > timeout_at
        Rails.cache.delete(redis_key)
        return false
      end

      # Store the user's answer in the cached data
      parsed_data["answer"] = user_message
      parsed_data["answered_at"] = Time.current.iso8601
      Rails.cache.write(redis_key, parsed_data.to_json, expires_in: 60)

      # Broadcast the user's response to show it in chat
      channel = "session_#{@session.id}"
      ActionCable.server.broadcast(channel, {
        type: "user_message",
        content: user_message
      })

      # Add to transcript
      @session.transcript << {
        "role" => "user",
        "content" => user_message,
        "timestamp" => Time.current.iso8601,
        "is_question_response" => true
      }
      @session.save!

      true
    rescue JSON::ParserError
      Rails.cache.delete(redis_key)
      false
    end
  end

  def set_agent
    @agent = Agent.by_slug(params[:agent_id]).first || Agent.find_by(id: params[:agent_id])
    render file: "public/404.html", status: :not_found unless @agent
  end

  def set_session
    @session = Session.find(params[:id])
  end

  def process_attachments
    attachment_ids = []

    [ params[:images], params[:files] ].compact.each do |file_list|
      Array(file_list).each do |upload|
        next unless upload.respond_to?(:content_type)

        attachment = @session.chat_attachments.create!(
          content_type: upload.content_type,
          filename: upload.original_filename,
          byte_size: upload.size
        )
        attachment.file.attach(upload)
        attachment_ids << attachment.id
      end
    end

    attachment_ids
  end
end
