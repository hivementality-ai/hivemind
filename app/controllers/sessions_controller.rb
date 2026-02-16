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

    # Handle file uploads (images + documents)
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

    ChatStreamJob.perform_later(@session.id, user_message.to_s, attachment_ids)
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
