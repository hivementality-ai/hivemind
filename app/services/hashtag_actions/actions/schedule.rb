# frozen_string_literal: true

module HashtagActions
  module Actions
    class Schedule < Base
      # Supports: #schedule 2h Check deployment
      #           #schedule 30m Standup reminder
      #           #schedule tomorrow Review PRs

      DURATION_PATTERN = /\A(\d+)(m|min|h|hr|d|day)s?\s+(.*)/im

      def execute
        return { response: "Schedule what? Use: #schedule <time> <task>\nExamples: #schedule 2h Check on deploy, #schedule 30m Standup", status: "no_payload" } if payload.blank?

        match = payload.match(DURATION_PATTERN)

        if match
          amount = match[1].to_i
          unit = match[2].downcase
          task = match[3].strip
          run_at = calculate_run_at(amount, unit)
        elsif payload.downcase.start_with?("tomorrow")
          task = payload.sub(/\Atomorrow\s*/i, "").strip
          run_at = Time.current.beginning_of_day + 1.day + 9.hours # 9 AM tomorrow
        else
          return { response: "Couldn't parse time. Try: #schedule 2h <task> or #schedule 30m <task>", status: "parse_error" }
        end

        return { response: "Task description is empty.", status: "no_task" } if task.blank?

        ScheduledTask.create!(
          name: task.truncate(100),
          schedule_type: "once",
          cron_expression: nil,
          next_run_at: run_at,
          task_type: "reminder",
          config: {
            "agent_id" => agent.id,
            "session_id" => session.id,
            "message" => task,
            "source" => "hashtag_action"
          },
          enabled: true
        )

        time_desc = if run_at < 1.day.from_now
                      "in #{distance_of_time(run_at)}"
                    else
                      run_at.strftime("%b %d at %I:%M %p")
                    end

        { response: "Scheduled: \"#{task.truncate(80)}\" — #{time_desc}", status: "scheduled" }
      rescue StandardError => e
        { response: "Failed to schedule: #{e.message}", status: "error" }
      end

      private

      def calculate_run_at(amount, unit)
        case unit
        when "m", "min" then amount.minutes.from_now
        when "h", "hr"  then amount.hours.from_now
        when "d", "day" then amount.days.from_now
        else amount.hours.from_now
        end
      end

      def distance_of_time(time)
        seconds = (time - Time.current).to_i
        if seconds < 3600
          "#{(seconds / 60.0).ceil} minutes"
        elsif seconds < 86_400
          hours = (seconds / 3600.0).round(1)
          "#{hours} hours"
        else
          days = (seconds / 86_400.0).round(1)
          "#{days} days"
        end
      end
    end
  end
end
