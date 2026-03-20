# frozen_string_literal: true

class SessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_agent, only: [ :create ]
  before_action :set_session, only: [ :show, :message, :interrupt, :update, :canvas, :export ]

  # GET /sessions — list all sessions
  def index
    @sessions = Session.includes(:agent)
                       .where(status: :active)
                       .order(Arel.sql("COALESCE(last_activity_at, created_at) DESC"))
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
        Plugins::Hooks.trigger("session_created", session: session)
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
    Plugins::Hooks.trigger("session_created", session: @session)

    redirect_to session_path(@session)
  end

  # GET /sessions/:id — show chat interface
  def show
    @agent = @session.agent
    @messages = @session.transcript || []
    @attachments = @session.chat_attachments.includes(file_attachment: :blob).index_by(&:message_index)
    @processing = Redis.current.get("session_processing:#{@session.id}") == "1"
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
    result = Sessions::ResolvePendingQuestion.call(session: @session, user_message: user_message)
    if result.success?
      head :ok
      return
    end

    attachment_ids = process_attachments

    # Broadcast user message immediately for instant feedback
    ActionCable.server.broadcast("session_#{@session.id}", { type: "user_message", content: user_message })

    # Enqueue the actual processing job
    ChatStreamJob.perform_later(@session.id, user_message.to_s, attachment_ids)
    head :ok
  end

  # PATCH /sessions/:id — rename a chat session
  def update
    new_title = params[:title].to_s.strip

    if new_title.blank? || new_title.length > 100
      render json: { error: "Title must be between 1 and 100 characters" }, status: :unprocessable_entity
      return
    end

    @session.update!(title: new_title)
    ActionCable.server.broadcast("session_#{@session.id}", { type: "title_update", title: new_title })
    render json: { title: new_title }
  end

  # GET /sessions/:id/canvas — live canvas view
  def canvas
    @agent = @session.agent
  end

  # GET /sessions/:id/export — download debug export as JSON
  def export
    result = Sessions::Export.call(session: @session)

    if result.success?
      filename = "session_#{@session.id}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      send_data result.data[:export].to_json, filename: filename, type: "application/json", disposition: "attachment"
    else
      redirect_to session_path(@session), alert: result.error
    end
  end

  # POST /sessions/:id/interrupt — cancel, redirect, or inject into active agent
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

    SessionSignal.set(@session.id, type: signal_type, message: message.presence)

    # Broadcast to UI immediately for visual feedback
    ActionCable.server.broadcast(
      "session_#{@session.id}",
      { type: "interrupt_sent", signal_type: signal_type, message: message.presence }
    )

    render json: { status: "signal_sent", type: signal_type }
  end

  private

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
