# frozen_string_literal: true

module Mobile
  class TeamChatsController < BaseController
    before_action :set_session, only: [ :show, :message, :interrupt ]

    def index
      @teams = Team.includes(:agents).order(:name)
    end

    def show
      @team = @session.team
      return redirect_to mobile_team_chats_path, alert: "Team not found" unless @team

      @agents = @team.agents.enabled.order(:name)
      @messages = @session.recent_messages(limit: 100)
    end

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

    def interrupt
      signal_type = params[:type].to_s.strip
      message = params[:message].to_s.strip

      unless SessionSignal::TYPES.include?(signal_type)
        render json: { error: "Invalid signal type" }, status: :unprocessable_entity
        return
      end

      if signal_type != "cancel" && message.blank?
        render json: { error: "Message required" }, status: :unprocessable_entity
        return
      end

      @session.agent_sessions.each do |agent_session|
        SessionSignal.set(agent_session.id, type: signal_type, message: message.presence)
        if agent_session.respond_to?(:sub_agent_tasks_as_parent)
          agent_session.sub_agent_tasks_as_parent.where(status: "running").find_each do |sat|
            SessionSignal.set(sat.child_session.id, type: signal_type, message: message.presence) if sat.child_session
          end
        end
      end

      ActionCable.server.broadcast(
        "team_chat_#{@session.id}",
        { type: "interrupt_sent", signal_type: signal_type, message: message.presence }
      )

      render json: { status: "signal_sent", type: signal_type }
    end

    private

    def set_session
      @session = TeamChatSession.find(params[:id])
    end
  end
end
