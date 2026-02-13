# frozen_string_literal: true

module Api
  module V1
    class SessionsController < ApiController
      before_action :set_session, only: [:show, :destroy]

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

      def show
        render json: @session.as_json(
          include: :agent,
          methods: [:transcript_summary]
        )
      end

      def destroy
        @session.destroy
        head :no_content
      end

      private

      def set_session
        @session = Session.find_by!(session_key: params[:id]) || Session.find(params[:id])
      end
    end
  end
end
