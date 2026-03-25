# frozen_string_literal: true

module Projects
  class ApprovalReminder
    def self.call(project:)
      new(project: project).call
    end

    def initialize(project:)
      @project = project
    end

    def call
      @project.milestones.awaiting_review.each do |milestone|
        next unless reminder_due?(milestone)

        if should_escalate?(milestone)
          send_escalation(milestone)
        else
          send_reminder(milestone)
        end

        milestone.update!(
          last_ping_at: Time.current,
          ping_count: milestone.ping_count + 1
        )
      end
    end

    private

    def reminder_due?(milestone)
      return true if milestone.last_ping_at.nil?
      return false if milestone.ping_count >= @project.approval_max_reminders

      milestone.last_ping_at < @project.approval_reminder_hours.hours.ago
    end

    def should_escalate?(milestone)
      return false if milestone.reviewed_at.present?

      first_ping = milestone.last_ping_at || milestone.updated_at
      time_waiting = Time.current - first_ping
      time_waiting > @project.approval_escalation_hours.hours
    end

    def send_reminder(milestone)
      blocked_count = @project.milestones.where(status: "pending")
                              .select { |m| m.depends_on.include?(milestone.id) }.size

      summary = "Reminder: \"#{milestone.title}\" is waiting for review. " \
                "#{blocked_count} downstream milestone(s) blocked."

      Projects::NotificationDispatcher.call(
        project: @project,
        milestone: milestone,
        message: summary,
        notification_type: "approval_reminder"
      )

      Projects::EventLogger.call(
        project: @project,
        milestone: milestone,
        event_type: "notification_sent",
        summary: summary
      )
    end

    def send_escalation(milestone)
      hours_waiting = ((Time.current - (milestone.last_ping_at || milestone.updated_at)) / 1.hour).round

      summary = "URGENT: \"#{milestone.title}\" has been waiting #{hours_waiting}h for review. " \
                "Project \"#{@project.title}\" is blocked."

      Projects::NotificationDispatcher.call(
        project: @project,
        milestone: milestone,
        message: summary,
        notification_type: "approval_escalation"
      )

      Projects::EventLogger.call(
        project: @project,
        milestone: milestone,
        event_type: "notification_sent",
        summary: "Escalation: #{summary}"
      )
    end
  end
end
