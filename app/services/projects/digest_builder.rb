# frozen_string_literal: true

module Projects
  class DigestBuilder
    def self.call(project:)
      new(project: project).call
    end

    def initialize(project:)
      @project = project
    end

    def call
      mode = @project.digest_mode
      return if mode == "realtime" || mode == "manual"

      return unless digest_due?(mode)

      events = collect_events_since_last_digest
      return if events.empty?

      summary = format_digest(events)

      Projects::NotificationDispatcher.call(
        project: @project,
        message: summary,
        notification_type: "digest"
      )

      @project.update!(metadata: @project.metadata.merge("last_digest_at" => Time.current.iso8601))
    end

    private

    def digest_due?(mode)
      last_digest = parse_time(@project.metadata["last_digest_at"])
      return true unless last_digest

      case mode
      when "hourly" then last_digest < 1.hour.ago
      when "daily" then last_digest < 1.day.ago
      else false
      end
    end

    def collect_events_since_last_digest
      since = parse_time(@project.metadata["last_digest_at"]) || 24.hours.ago
      @project.events.since(since).recent.limit(50)
    end

    def format_digest(events)
      lines = [ "📋 Project Update: #{@project.title}", "" ]

      events.group_by(&:event_type).each do |type, group|
        lines << "**#{type.titleize}** (#{group.size})"
        group.first(5).each { |e| lines << "  - #{e.summary}" }
        lines << ""
      end

      lines << "Progress: #{@project.progress_percentage}% complete"
      lines.join("\n")
    end

    def parse_time(value)
      return nil if value.blank?

      Time.parse(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
