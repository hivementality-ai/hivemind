# frozen_string_literal: true

module HashtagActions
  module Actions
    class Handoff < Base
      def execute
        return { response: "Handoff to whom? Use: #handoff @AgentName", status: "no_payload" } if payload.blank?

        agent_name = payload.sub(/\A@/, "").strip
        target = Agent.visible.enabled.where("LOWER(name) = ?", agent_name.downcase).first
        target ||= Agent.visible.enabled.where("LOWER(REPLACE(name, ' ', '_')) = ?", agent_name.downcase.tr(" ", "_")).first

        return { response: "Agent \"#{agent_name}\" not found. Check available agents with #status.", status: "not_found" } unless target
        return { response: "Can't hand off to myself.", status: "self_handoff" } if target.id == agent.id

        # Create a new session with the target agent, carrying context
        new_session = Session.create!(
          agent: target,
          session_key: "handoff-#{session.id}-to-#{target.id}-#{Time.current.to_i}",
          title: "Handoff from #{agent.name}",
          status: "active",
          transcript: [],
          metadata: {
            "handoff_from_agent" => agent.id,
            "handoff_from_session" => session.id,
            "handoff_at" => Time.current.iso8601
          }
        )

        # Add context summary to new session
        summary = "This conversation was handed off from #{agent.name}. Previous context:\n"
        recent = (session.transcript || []).last(10).map { |m| "[#{m['role']}] #{m['content'].to_s.truncate(200)}" }
        summary += recent.join("\n")

        new_session.append_transcript({ "role" => "system", "content" => summary })

        # Mark old session
        session.update!(status: "handed_off", metadata: (session.metadata || {}).merge(
          "handed_off_to_agent" => target.id,
          "handed_off_to_session" => new_session.id
        ))

        {
          response: "Handed off to #{target.name}. Session ##{new_session.id} created with conversation context.",
          status: "handed_off"
        }
      end
    end
  end
end
