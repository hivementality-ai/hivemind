# frozen_string_literal: true

class TaskEvent < ApplicationRecord
  EVENT_TYPES = %w[
    status_change hook_fired comment_added assigned
    dependency_added dependency_removed checklist_updated created
    attachment_added attachment_removed
    archived auto_assigned artifact_added artifact_removed
    transition_requested pipeline_failed
    updated hook_added hook_removed
  ].freeze

  belongs_to :task
  belongs_to :agent, optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :summary, presence: true

  scope :chronological, -> { order(created_at: :asc) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :since, ->(time) { where("created_at >= ?", time) }
  scope :before, ->(time) { where("created_at <= ?", time) }

  # Human-readable formatting for the activity feed.
  def to_activity_line
    timestamp = created_at.strftime("%Y-%m-%d %H:%M")
    actor = agent&.name || "System"
    "[#{timestamp}] #{actor}: #{summary}"
  end
end
