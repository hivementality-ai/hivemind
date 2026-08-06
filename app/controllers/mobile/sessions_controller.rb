# frozen_string_literal: true

module Mobile
  class SessionsController < BaseController
    include SessionChatActions

    before_action :set_session, only: [ :show, :message, :interrupt ]

    def index
      @sessions = Session.includes(:agent)
                         .where(status: :active)
                         .order(last_activity_at: :desc)
                         .limit(50)
      @agents = Agent.enabled.order(:name)
    end

    def create
      agent = resolve_agent(params[:agent_id])
      unless agent
        redirect_to mobile_sessions_path, alert: 'Agent not found'
        return
      end

      session = create_chat_session(agent: agent, user: current_user)

      redirect_to mobile_session_path(session)
    end

    def show
      @agent = @session.agent
      @messages = @session.transcript || []
      @attachments = @session.chat_attachments.includes(file_attachment: :blob).index_by(&:message_index)
      @processing = Redis.current.get("session_processing:#{@session.id}") == "1"
    end

    def message
      result = process_chat_message(
        session: @session,
        message: params[:message],
        images: params[:images],
        files: params[:files]
      )

      if result == :blank
        head :unprocessable_entity
      else
        head :ok
      end
    end

    def interrupt
      result = send_session_interrupt(session: @session, type: params[:type], message: params[:message])

      if result[:error]
        render json: { error: result[:error] }, status: :unprocessable_entity
      else
        render json: { status: "signal_sent", type: result[:type] }
      end
    end

    private

    def set_session
      @session = Session.find(params[:id])
    end
  end
end
