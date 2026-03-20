# frozen_string_literal: true

module Projects
  class NotificationDispatcher
    def self.call(project:, message:, milestone: nil, notification_type: "info")
      new(project: project, message: message, milestone: milestone,
          notification_type: notification_type).call
    end

    def initialize(project:, message:, milestone: nil, notification_type: "info")
      @project = project
      @message = message
      @milestone = milestone
      @notification_type = notification_type
    end

    def call
      ProjectNotificationJob.perform_later(
        @project.id,
        @message,
        @milestone&.id,
        @notification_type
      )
    end
  end
end
