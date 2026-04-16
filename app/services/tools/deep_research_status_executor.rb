# frozen_string_literal: true

module Tools
  class DeepResearchStatusExecutor < BaseExecutor
    def call
      action = input["action"].to_s.strip.presence || "status"
      task_key = input["task_key"].to_s.strip

      case action
      when "status"
        return ServiceResponse.failure(error: "No task_key provided") if task_key.empty?
        check_status(task_key)
      when "list"
        list_sessions
      when "cancel"
        return ServiceResponse.failure(error: "No task_key provided") if task_key.empty?
        cancel_session(task_key)
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: status, list, cancel")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Deep research status failed: #{e.message}")
    end

    private

    def check_status(task_key)
      rs = find_research_session(task_key)
      return rs if rs.is_a?(ServiceResponse)

      output = []
      output << "Research Session: #{task_key}"
      output << "Query: #{rs.query.truncate(100)}"
      output << "Status: #{format_status(rs.status)}"
      output << "Depth: #{rs.depth}"
      output << "Phase: #{rs.current_phase}" if rs.current_phase.present?
      output << "Sources: #{rs.sources_count}"
      output << "Duration: #{rs.duration_seconds}s" if rs.started_at

      if rs.active?
        output << ""
        output << "⏳ Research is still in progress. Do NOT check again for at least 30 seconds. Work on something else and come back later."
      end

      if rs.progress_log.present?
        output << ""
        output << "=== Recent Progress ==="
        rs.progress_log.last(5).each do |entry|
          output << "- #{entry['message'] || entry[:message]}"
        end
      end

      if rs.completed? && rs.report.present?
        output << ""
        output << "=== Report ==="
        output << rs.report.last(4000)
      end

      if rs.failed? && rs.error_message.present?
        output << ""
        output << "=== Error ==="
        output << rs.error_message
      end

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    end

    def list_sessions
      sessions = if agent
                   ResearchSession.for_agent(agent).recent(5)
      else
                   ResearchSession.recent(5)
      end

      if sessions.any?
        output = [ "Research Sessions:\n" ]
        sessions.each do |rs|
          icon = format_status_icon(rs.status)
          duration_text = rs.duration_seconds ? "(#{rs.duration_seconds}s)" : ""
          output << "#{icon} [#{rs.task_key}] #{rs.query.truncate(60)} #{duration_text}"
        end
        ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No research sessions found.", exit_code: 0 })
      end
    end

    def cancel_session(task_key)
      rs = find_research_session(task_key)
      return rs if rs.is_a?(ServiceResponse)

      unless rs.active?
        return ServiceResponse.failure(error: "Session #{task_key} is not active (status: #{rs.status})")
      end

      rs.update!(status: "cancelled", completed_at: Time.current)

      ServiceResponse.success(data: {
        output: "Cancelled research session #{task_key}",
        exit_code: 0
      })
    end

    def find_research_session(task_key)
      rs = ResearchSession.find_by(task_key: task_key)
      return ServiceResponse.failure(error: "Research session not found: #{task_key}") unless rs

      unless rs.agent == agent || agent.nil?
        return ServiceResponse.failure(error: "Session #{task_key} not found or not accessible")
      end

      rs
    end

    def format_status(status)
      case status
      when "queued" then "⏳ Queued"
      when "running" then "🔄 Running"
      when "completed" then "✅ Completed"
      when "failed" then "❌ Failed"
      when "cancelled" then "🚫 Cancelled"
      else status
      end
    end

    def format_status_icon(status)
      case status
      when "queued" then "⏳"
      when "running" then "🔄"
      when "completed" then "✅"
      when "failed" then "❌"
      when "cancelled" then "🚫"
      else "❓"
      end
    end
  end
end
