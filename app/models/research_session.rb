# frozen_string_literal: true

class ResearchSession < ApplicationRecord
  belongs_to :agent
  belongs_to :session

  STATUSES = %w[queued running completed failed cancelled].freeze
  DEPTHS = %w[quick standard deep].freeze
  FOCUSES = %w[general technical scientific news financial].freeze
  OUTPUT_FORMATS = %w[report bullet_points detailed_analysis executive_summary].freeze

  validates :query, presence: true
  validates :task_key, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :depth, inclusion: { in: DEPTHS }
  validates :focus, inclusion: { in: FOCUSES }
  validates :output_format, inclusion: { in: OUTPUT_FORMATS }

  scope :active, -> { where(status: %w[queued running]) }
  scope :recent, ->(limit = 5) { order(created_at: :desc).limit(limit) }
  scope :for_agent, ->(agent) { where(agent: agent) }

  def log_progress(message)
    entry = { message: message, timestamp: Time.current.iso8601 }
    self.progress_log = (progress_log || []) + [ entry ]
    save!

    ActionCable.server.broadcast(resolve_channel, {
      type: "research_progress",
      task_key: task_key,
      message: message,
      timestamp: entry[:timestamp]
    })
  end

  def add_source(hash)
    self.sources = (sources || []) + [ hash ]
    self.sources_count = sources.size
    save!
  end

  def add_finding(hash)
    self.findings = (findings || []) + [ hash ]
    save!
  end

  def complete!(report_text)
    update!(
      status: "completed",
      report: report_text,
      completed_at: Time.current
    )

    ActionCable.server.broadcast(resolve_channel, {
      type: "research_complete",
      task_key: task_key,
      query: query.truncate(100),
      sources_count: sources_count,
      timestamp: Time.current.iso8601
    })
  end

  def fail!(error)
    update!(
      status: "failed",
      error_message: error,
      completed_at: Time.current
    )
  end

  # @return [Array<Hash>] quoted passages not found in any source, or found only in a source other than the cited one
  def flagged_quotes
    Array(quote_checks["results"]).select { |check| %w[unverified other_source].include?(check["status"]) }
  end

  # @return [String] marker text for a flagged quote, naming the host where it was actually found
  def quote_flag_label(check)
    return "(not found in source)" unless check["status"] == "other_source"

    host = URI.parse(check["source_url"].to_s).host.presence || check["source_url"]
    "(found in a different source: #{host})"
  rescue URI::InvalidURIError
    "(found in a different source: #{check['source_url']})"
  end

  # @return [String, nil] e.g. "1 of 9 quotes could not be found, 1 was in a different source than cited"
  def quote_check_summary
    summary = quote_checks["summary"] || {}
    missing = summary["unverified"].to_i
    misattributed = summary["other_source"].to_i
    return if missing.zero? && misattributed.zero?

    total = summary["total"].to_i
    noun = "quote".pluralize(total)
    different = "#{misattributed == 1 ? 'was' : 'were'} in a different source than cited"
    if misattributed.zero?
      "#{missing} of #{total} #{noun} could not be found in their sources"
    elsif missing.zero?
      "#{misattributed} of #{total} #{noun} #{different}"
    else
      "#{missing} of #{total} #{noun} could not be found, #{misattributed} #{different}"
    end
  end

  def cancelled?
    reload
    status == "cancelled"
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def active?
    %w[queued running].include?(status)
  end

  def duration_seconds
    return nil unless started_at
    ((completed_at || Time.current) - started_at).round(1)
  end

  private

  def resolve_channel
    if session.respond_to?(:team_chat_session_id) && session.team_chat_session_id.present?
      "team_chat_#{session.team_chat_session_id}"
    else
      "session_#{session.id}"
    end
  end
end
