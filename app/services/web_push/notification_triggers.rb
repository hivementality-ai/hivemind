# frozen_string_literal: true

module WebPush
  class NotificationTriggers
    class << self
      # Called when an agent finishes responding in a session
      def agent_response(session:, content:)
        user = find_session_user(session)
        return unless user&.notification_enabled?("agent_responses")
        return if user_has_app_focused?(user)

        notify_user(
          user: user,
          category: "agent_responses",
          title: session.agent.name,
          body: content.to_s.truncate(100),
          url: "/m/sessions/#{session.id}",
          tag: "agent-response-#{session.id}",
          session_id: session.id,
          agent_id: session.agent_id
        )
      end

      # Called when a spawn/delegate task completes
      def task_completed(task:)
        session = task.parent_session
        return unless session

        user = find_session_user(session)
        return unless user&.notification_enabled?("task_completions")

        notify_user(
          user: user,
          category: "task_completions",
          title: "Task Complete",
          body: "#{task.child_session&.agent&.name} finished: #{task.task.to_s.truncate(80)}",
          url: "/m/sessions/#{session.id}",
          tag: "task-complete-#{task.id}",
          session_id: session.id,
          agent_id: task.child_session&.agent_id
        )
      end

      # Called when a coding agent task finishes
      def coding_task_done(task:)
        user = find_session_user(task.session)
        return unless user&.notification_enabled?("task_completions")

        notify_user(
          user: user,
          category: "task_completions",
          title: "Code Task Done",
          body: "#{task.agent&.name || 'Agent'} finished: #{task.description.to_s.truncate(80)}",
          url: "/m/sessions/#{task.session_id}",
          tag: "coding-task-#{task.id}",
          session_id: task.session_id,
          agent_id: task.agent&.id
        )
      end

      # Called when budget threshold is reached
      def budget_alert(agent:, percentage:)
        User.where(role: [ :admin, :owner ]).find_each do |user|
          next unless user.notification_enabled?("budget_alerts")

          notify_user(
            user: user,
            category: "budget_alerts",
            title: "Budget Warning",
            body: "#{agent.name} at #{percentage}% of daily limit",
            url: "/m/agents/#{agent.slug}",
            tag: "budget-alert-#{agent.id}",
            agent_id: agent.id
          )
        end
      end

      # Called when heartbeat finds something
      def heartbeat_finding(finding_summary:)
        User.where(role: [ :admin, :owner ]).find_each do |user|
          next unless user.notification_enabled?("heartbeat_findings")

          notify_user(
            user: user,
            category: "heartbeat_findings",
            title: "Heartbeat",
            body: finding_summary.to_s.truncate(100),
            url: "/m/activity",
            tag: "heartbeat-#{SecureRandom.hex(4)}"
          )
        end
      end

      # Called when an agent asks the user a question via the ask_user tool
      # and is blocked waiting on a response.
      def needs_input(session:, questions: nil)
        user = find_session_user(session)
        return unless user&.notification_enabled?("needs_input")

        first_question = Array(questions).first
        question_text = first_question.is_a?(Hash) ? (first_question["question"] || first_question[:question]) : nil

        notify_user(
          user: user,
          category: "needs_input",
          title: "#{session.agent&.name || 'Agent'} needs your input",
          body: question_text.to_s.presence&.truncate(100) || "Waiting on your response",
          url: "/m/sessions/#{session.id}",
          tag: "needs-input-#{session.id}",
          session_id: session.id,
          agent_id: session.agent_id
        )
      end

      # Called when a session errors out
      def session_error(session:, message:)
        user = find_session_user(session)
        return unless user&.notification_enabled?("errors")

        notify_user(
          user: user,
          category: "errors",
          title: "#{session.agent&.name || 'Agent'} hit an error",
          body: message.to_s.truncate(100),
          url: "/m/sessions/#{session.id}",
          tag: "session-error-#{session.id}",
          session_id: session.id,
          agent_id: session.agent_id
        )
      end

      private

      def find_session_user(session)
        return nil unless session

        user_id = session.metadata&.dig("started_by")
        User.find_by(id: user_id)
      end

      def user_has_app_focused?(user)
        # Cannot reliably determine if PWA is focused from server-side
        # Push notifications handle this client-side with visibilityState
        false
      end

      # Sends the existing web push notification and, alongside it, broadcasts
      # the same notification to the user's NotificationChannel stream so
      # any connected desktop/other client gets it too.
      def notify_user(user:, category:, title:, body:, url:, tag:, session_id: nil, agent_id: nil)
        user.notify(title: title, body: body, url: url, tag: tag)
        broadcast_notification(
          user: user,
          category: category,
          title: title,
          body: body,
          tag: tag,
          session_id: session_id,
          agent_id: agent_id
        )
      end

      def broadcast_notification(user:, category:, title:, body:, tag:, session_id: nil, agent_id: nil)
        payload = {
          category: category,
          title: title,
          body: body,
          tag: tag,
          timestamp: Time.current.iso8601
        }
        payload[:session_id] = session_id if session_id
        payload[:agent_id] = agent_id if agent_id

        ActionCable.server.broadcast("notifications_user_#{user.id}", payload)
      end
    end
  end
end
