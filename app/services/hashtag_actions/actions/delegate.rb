# frozen_string_literal: true

module HashtagActions
  module Actions
    class Delegate < Base
      def execute
        return { response: "Delegate what? Use: #delegate @AgentName <task>", status: "no_payload" } if payload.blank?

        # Parse @AgentName from payload
        match = payload.match(/\A@(\S+)\s*(.*)/m)
        return { response: "Use: #delegate @AgentName <task>", status: "parse_error" } unless match

        agent_name = match[1]
        task = match[2].strip
        return { response: "What should #{agent_name} do? Add a task description.", status: "no_task" } if task.blank?

        target = Agent.visible.enabled.where("LOWER(name) = ?", agent_name.downcase).first
        target ||= Agent.visible.enabled.where("LOWER(REPLACE(name, ' ', '_')) = ?", agent_name.downcase.tr(" ", "_")).first
        return { response: "Agent \"#{agent_name}\" not found.", status: "not_found" } unless target

        # Use the delegate tool's logic — synchronous call
        delegate_session = Session.create!(
          agent: target,
          session_key: "delegate-#{session.id}-#{target.id}-#{Time.current.to_i}",
          title: "Delegated from #{agent.name}",
          status: "active"
        )

        result = Sessions::Chat.call(
          session: delegate_session,
          message: "You've been delegated a task by #{agent.name}: #{task}"
        )

        if result.success?
          reply = result.data[:content].to_s.truncate(500)
          { response: "#{target.name} says:\n#{reply}", status: "delegated" }
        else
          { response: "Delegation to #{target.name} failed: #{result.error}", status: "error" }
        end
      rescue StandardError => e
        { response: "Delegation error: #{e.message}", status: "error" }
      end
    end
  end
end
