# frozen_string_literal: true

class ProjectNotificationJob < ApplicationJob
  queue_as :default

  def perform(project_id, message, milestone_id = nil, notification_type = "info")
    project = Project.find_by(id: project_id)
    return unless project

    milestone = milestone_id ? ProjectMilestone.find_by(id: milestone_id) : nil

    # Send web push notification to project owner
    if defined?(WebPush::Sender)
      url = milestone ? "/projects/#{project.id}" : "/projects/#{project.id}"
      project.user.notify(
        title: "Hivemind Project: #{project.title}",
        body: message.truncate(100),
        url: url,
        tag: "project-#{project.id}-#{notification_type}"
      )
    end

    # Broadcast to project ActionCable channel
    ActionCable.server.broadcast("project_#{project.id}", {
      type: "notification",
      notification_type: notification_type,
      message: message,
      milestone_id: milestone&.id,
      timestamp: Time.current.iso8601
    })

    # Try channel delivery (Slack, Discord, etc.)
    deliver_via_channel(project, message, notification_type)
  end

  private

  def deliver_via_channel(project, message, notification_type)
    channel_type = project.notification_pref("channel")
    channel_target = project.notification_pref("channel_target")
    return unless channel_type.present? && channel_target.present?

    channel = Channel.find_by(channel_type: channel_type, enabled: true)
    return unless channel

    formatted = format_for_channel(message, notification_type)

    MessageExecutor.new(
      channel: channel,
      target: channel_target,
      message: formatted
    ).call
  rescue StandardError => e
    Rails.logger.warn("[ProjectNotificationJob] Channel delivery failed: #{e.message}")
  end

  def format_for_channel(message, notification_type)
    case notification_type
    when "approval_reminder", "approval_escalation"
      "#{message}\n\nReply `#approve` or `#deny` to respond."
    else
      message
    end
  end
end
