# frozen_string_literal: true

module Internal
  class ToolsController < ActionController::API
    before_action :authenticate_internal!

    # POST /internal/tools/execute
    def execute
      tool = Tool.enabled.find_by(name: params[:tool_name])
      unless tool
        return render json: { success: false, error: "Unknown tool: #{params[:tool_name]}" }, status: :unprocessable_entity
      end

      agent = Agent.find_by(id: params[:agent_id])
      session = Session.find_by(id: params[:session_id])

      unless agent && session
        return render json: { success: false, error: "Agent or session not found" }, status: :unprocessable_entity
      end

      channel = "session_#{session.id}"

      # Broadcast tool start
      ActionCable.server.broadcast(channel, { type: "tool_start", tool: tool.name, input: params[:input]&.to_unsafe_h || {} })

      # Execute the tool
      result = Tools::Executor.call(
        tool: tool,
        input: params[:input]&.to_unsafe_h || {},
        agent: agent,
        session: session
      )

      if result.success?
        output = result.data[:output].to_s
        ActionCable.server.broadcast(channel, { type: "tool_result", tool: tool.name, output: output.truncate(500), success: true })
        render json: { success: true, output: output }
      else
        ActionCable.server.broadcast(channel, { type: "tool_result", tool: tool.name, output: result.error.truncate(500), success: false })
        render json: { success: false, error: result.error }, status: :unprocessable_entity
      end
    end

    private

    def authenticate_internal!
      secret = ENV["INTERNAL_API_SECRET"]
      unless secret.present?
        Rails.logger.error("INTERNAL_API_SECRET not configured")
        return render json: { success: false, error: "Internal API not configured" }, status: :service_unavailable
      end

      token = request.headers["Authorization"]&.sub(/^Bearer\s+/, "")
      unless ActiveSupport::SecurityUtils.secure_compare(token.to_s, secret)
        render json: { success: false, error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
