# frozen_string_literal: true

module Mobile
  class ActivityController < BaseController
    def index
      @events = build_activity_feed
    end

    private

    def build_activity_feed
      events = []

      # Recent messages across sessions
      Session.includes(:agent)
             .where(status: :active)
             .where("last_activity_at > ?", 24.hours.ago)
             .order(last_activity_at: :desc)
             .limit(20)
             .each do |session|
        last_msg = session.transcript&.last
        next unless last_msg
        events << {
          type: "message",
          title: session.agent.name,
          body: last_msg["content"]&.truncate(100),
          timestamp: session.last_activity_at,
          url: "/m/sessions/#{session.id}",
          icon: "chat"
        }
      end

      # Agent status changes
      Agent.enabled.where.not(status: :idle).each do |agent|
        events << {
          type: "agent_status",
          title: agent.name,
          body: "Status: #{agent.status}",
          timestamp: agent.updated_at,
          url: "/m/agents/#{agent.slug}",
          icon: "agent"
        }
      end

      # Recent audit log entries
      if defined?(AuditLog)
        AuditLog.recent.limit(20).each do |log|
          events << {
            type: "audit",
            title: log.action.to_s.titleize,
            body: "#{log.resource} by #{log.actor_type}",
            timestamp: log.created_at,
            url: "/m/activity",
            icon: "activity"
          }
        end
      end

      # Sub-agent task completions
      SubAgentTask.where(status: [ "completed", "failed" ])
                  .where("updated_at > ?", 24.hours.ago)
                  .order(updated_at: :desc)
                  .limit(10)
                  .each do |task|
        events << {
          type: "task",
          title: "Task #{task.status.capitalize}",
          body: task.task_description.to_s.truncate(100),
          timestamp: task.updated_at,
          url: task.parent_session ? "/m/sessions/#{task.parent_session.id}" : "/m/activity",
          icon: "task"
        }
      end

      events.sort_by { |e| e[:timestamp] }.reverse.first(50)
    end
  end
end
