# frozen_string_literal: true

module Tools
  class SessionsSendExecutor < BaseExecutor
    # Send a message into another session (by session_key or agent name)
    def call
      session_key = input["session_key"].to_s.strip
      agent_name = input["agent"].to_s.strip
      message = input["message"].to_s.strip

      return ServiceResponse.failure(error: "No message provided") if message.empty?

      session = find_session(session_key, agent_name)
      return ServiceResponse.failure(error: "Session not found. Provide session_key or agent name.") unless session

      target_agent = session.agent
      return ServiceResponse.failure(error: "No agent for session") unless target_agent

      result = Sessions::Chat.call(session: session, message: message, agent: target_agent)

      if result.success?
        reply = result.data[:content].to_s.truncate(3000)
        ServiceResponse.success(data: {
          output: "Sent to #{target_agent.name} (session #{session.session_key}).\nReply: #{reply}",
          exit_code: 0
        })
      else
        ServiceResponse.failure(error: "Send failed: #{result.error}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Sessions send failed: #{e.message}")
    end

    private

    def find_session(session_key, agent_name)
      if session_key.present?
        Session.find_by(session_key: session_key)
      elsif agent_name.present?
        agent = Agent.visible.enabled.where("LOWER(name) = ?", agent_name.downcase).first
        agent && Session.where(agent: agent).order(updated_at: :desc).first
      end
    end
  end
end
