# frozen_string_literal: true

module Projects
  class DeadlineChecker
    def self.call(project:)
      new(project: project).call
    end

    def initialize(project:)
      @project = project
    end

    def call
      return unless @project.deadline.present?
      return if @project.status.in?(%w[completed cancelled])

      warning_hours = case @project.priority
      when "urgent" then 24
      when "high" then 36
      when "normal" then 48
      else 72
      end

      return unless @project.deadline < warning_hours.hours.from_now
      return if already_warned?

      summary = "Project \"#{@project.title}\" deadline is #{time_until_deadline}."

      Projects::NotificationDispatcher.call(
        project: @project,
        message: summary,
        notification_type: "deadline_warning"
      )

      Projects::EventLogger.call(
        project: @project,
        event_type: "deadline_warning",
        summary: summary
      )
    end

    private

    def already_warned?
      @project.events
              .where(event_type: "deadline_warning")
              .where("created_at > ?", 12.hours.ago)
              .any?
    end

    def time_until_deadline
      hours = ((@project.deadline - Time.current) / 1.hour).round
      if hours <= 0
        "overdue"
      elsif hours < 24
        "in #{hours} hours"
      else
        "in #{(hours / 24.0).round(1)} days"
      end
    end
  end
end
