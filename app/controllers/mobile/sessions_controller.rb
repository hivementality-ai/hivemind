# frozen_string_literal: true

module Mobile
  class SessionsController < BaseController
    before_action :set_session, only: [ :show, :message, :interrupt ]

    def index
      @sessions = Session.includes(:agent)
                         .where(status: :active)
                         .order(last_activity_at: :desc)
                         .limit(50)
      @agents = Agent.enabled.order(:name)
    end

    def show
      @agent = @session.agent
      @messages = @session.transcript || []
      @attachments = @session.chat_attachments.includes(file_attachment: :blob).index_by(&:message_index)
      @processing = Redis.current.get("session_processing:#{@session.id}") == "1"
    end

    def message
      user_message = params[:message]&.strip
      has_attachments = params[:images].present? || params[:files].present?

      if user_message.blank? && !has_attachments
        head :unprocessable_entity
        return
      end

      result = Sessions::ResolvePendingQuestion.call(session: @session, user_message: user_message)
      if result.success?
        head :ok
        return
      end

      attachment_ids = process_attachments

      ActionCable.server.broadcast("session_#{@session.id}", { type: "user_message", content: user_message })
      ChatStreamJob.perform_later(@session.id, user_message.to_s, attachment_ids)
      head :ok
    end

    def interrupt
      signal_type = params[:type].to_s.strip
      message = params[:message].to_s.strip

      unless SessionSignal::TYPES.include?(signal_type)
        render json: { error: "Invalid signal type" }, status: :unprocessable_entity
        return
      end

      if signal_type != "cancel" && message.blank?
        render json: { error: "Message required for #{signal_type}" }, status: :unprocessable_entity
        return
      end

      SessionSignal.set(@session.id, type: signal_type, message: message.presence)

      if @session.respond_to?(:sub_agent_tasks_as_parent)
        @session.sub_agent_tasks_as_parent.where(status: "running").find_each do |sat|
          SessionSignal.set(sat.child_session.id, type: signal_type, message: message.presence) if sat.child_session
        end
      end

      ActionCable.server.broadcast(
        "session_#{@session.id}",
        { type: "interrupt_sent", signal_type: signal_type, message: message.presence }
      )

      render json: { status: "signal_sent", type: signal_type }
    end

    private

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
end
