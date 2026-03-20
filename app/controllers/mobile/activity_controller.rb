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
          title: session.agent&.name || "Agent",
          body: last_msg["content"]&.truncate(100),
          timestamp: session.last_activity_at || session.updated_at,
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
        begin
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
        rescue StandardError => e
          Rails.logger.warn("[Mobile::Activity] AuditLog query failed: #{e.message}")
        end
      end

      # Sub-agent task completions
      SubAgentTask.where(status: %w[completed failed])
                  .where("updated_at > ?", 24.hours.ago)
                  .order(updated_at: :desc)
                  .limit(10)
                  .each do |sat|
        events << {
          type: "task",
          title: "Task #{sat.status.capitalize}",
          body: sat.task.to_s.truncate(100),
          timestamp: sat.updated_at,
          url: sat.parent_session_id ? "/m/sessions/#{sat.parent_session_id}" : "/m/activity",
          icon: "task"
        }
      end

      events.sort_by { |e| e[:timestamp] || Time.at(0) }.reverse.first(50)
    end
  end
end
