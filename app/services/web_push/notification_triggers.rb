# frozen_string_literal: true

module WebPush
  class NotificationTriggers
    class << self
      # Called when an agent finishes responding in a session
      def agent_response(session:, content:)
        user = find_session_user(session)
        return unless user&.notification_enabled?("agent_responses")
        return if user_has_app_focused?(user)

        user.notify(
          title: session.agent.name,
          body: content.to_s.truncate(100),
          url: "/m/sessions/#{session.id}",
          tag: "agent-response-#{session.id}"
        )
      end

      # Called when a spawn/delegate task completes
      def task_completed(task:)
        session = task.parent_session
        return unless session

        user = find_session_user(session)
        return unless user&.notification_enabled?("task_completions")

        user.notify(
          title: "Task Complete",
          body: "#{task.child_session&.agent&.name} finished: #{task.task.to_s.truncate(80)}",
          url: "/m/sessions/#{session.id}",
          tag: "task-complete-#{task.id}"
        )
      end

      # Called when a coding agent task finishes
      def coding_task_done(task:)
        user = find_session_user(task.session)
        return unless user&.notification_enabled?("task_completions")

        user.notify(
          title: "Code Task Done",
          body: "#{task.agent&.name || 'Agent'} finished: #{task.description.to_s.truncate(80)}",
          url: "/m/sessions/#{task.session_id}",
          tag: "coding-task-#{task.id}"
        )
      end

      # Called when budget threshold is reached
      def budget_alert(agent:, percentage:)
        User.where(role: [ :admin, :owner ]).find_each do |user|
          next unless user.notification_enabled?("budget_alerts")

          user.notify(
            title: "Budget Warning",
            body: "#{agent.name} at #{percentage}% of daily limit",
            url: "/m/agents/#{agent.slug}",
            tag: "budget-alert-#{agent.id}"
          )
        end
      end

      # Called when heartbeat finds something
      def heartbeat_finding(finding_summary:)
        User.where(role: [ :admin, :owner ]).find_each do |user|
          next unless user.notification_enabled?("heartbeat_findings")

          user.notify(
            title: "Heartbeat",
            body: finding_summary.to_s.truncate(100),
            url: "/m/activity",
            tag: "heartbeat-#{SecureRandom.hex(4)}"
          )
        end
      end

      private

      def find_session_user(session)
        user_id = session.metadata&.dig("started_by")
        User.find_by(id: user_id)
      end

      def user_has_app_focused?(user)
        # Cannot reliably determine if PWA is focused from server-side
        # Push notifications handle this client-side with visibilityState
        false
      end
    end
  end
end
