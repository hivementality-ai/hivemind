# frozen_string_literal: true

module Api
  module V1
    class SessionsController < ApiController
      include SessionChatActions

      before_action :set_session, only: [ :show, :destroy, :export, :messages, :interrupt, :update ]

      def index
        @sessions = Session.includes(:agent)
                          .order(created_at: :desc)
                          .page(params[:page])
                          .per(params[:per_page] || 25)

        if params[:agent_id].present?
          @sessions = @sessions.where(agent_id: params[:agent_id])
        end

        render json: {
          sessions: @sessions.as_json(include: :agent, except: :transcript),
          meta: {
            current_page: @sessions.current_page,
            total_pages: @sessions.total_pages,
            total_count: @sessions.total_count
          }
        }
      end

      # GET /api/v1/sessions/:id — hydration call: full transcript + processing
      # flag, so the desktop client can render history before subscribing to
      # the cable channel (and again after every reconnect).
      def show
        render json: @session.as_json(include: :agent).merge(
          transcript: @session.transcript || [],
          processing: Redis.current.get("session_processing:#{@session.id}") == "1"
        )
      end

      # POST /api/v1/sessions — {agent_id} (accepts id or slug)
      def create
        agent = resolve_agent(params[:agent_id])
        return render json: { error: "Agent not found" }, status: :not_found unless agent

        session = create_chat_session(agent: agent, user: current_user)
        render json: session.as_json(include: :agent), status: :created
      end

      # PATCH /api/v1/sessions/:id — rename
      def update
        result = rename_chat_session(session: @session, title: params[:title])

        if result[:error]
          render json: { error: result[:error] }, status: :unprocessable_entity
        else
          render json: { title: result[:title] }
        end
      end

      # POST /api/v1/sessions/:id/messages
      def messages
        result = process_chat_message(
          session: @session,
          message: params[:message],
          images: params[:images],
          files: params[:files]
        )

        if result == :blank
          render json: { error: "Message or attachment required" }, status: :unprocessable_entity
        else
          render json: { status: "ok" }, status: :accepted
        end
      end

      # POST /api/v1/sessions/:id/interrupt
      def interrupt
        result = send_session_interrupt(session: @session, type: params[:type], message: params[:message])

        if result[:error]
          render json: { error: result[:error] }, status: :unprocessable_entity
        else
          render json: { status: "signal_sent", type: result[:type] }
        end
      end

      def export
        result = Sessions::Export.call(session: @session)

        if result.success?
          render json: result.data[:export]
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def destroy
        @session.destroy
        head :no_content
      end

      private

      def set_session
        @session = Session.find_by(session_key: params[:id]) || Session.find(params[:id])
      end
    end
  end
end
