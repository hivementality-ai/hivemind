# frozen_string_literal: true

class Task < ApplicationRecord
  STATUSES   = %w[backlog todo in_progress review done].freeze
  PRIORITIES = %w[low medium high urgent].freeze

  belongs_to :created_by_agent, class_name: "Agent", optional: true
  belongs_to :assigned_to_agent, class_name: "Agent", optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }

  before_validation :set_completed_at

  scope :open,       -> { where.not(status: "done") }
  scope :done,       -> { where(status: "done") }
  scope :for_agent,  ->(agent) { where(assigned_to_agent: agent) }
  scope :by_status,  ->(s) { where(status: s) }
  scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END")) }
  scope :recent,     -> { order(created_at: :desc) }

  def add_comment(author_name:, body:)
    entry = {
      "author"     => author_name,
      "body"       => body,
      "created_at" => Time.current.iso8601
    }
    self.comments = (comments || []) + [entry]
    save!
    entry
  end

  def assigned?
    assigned_to_agent_id.present?
  end

  def overdue?
    due_at.present? && due_at < Time.current && status != "done"
  end

  def to_summary
    parts = ["[##{id}] #{title} (#{status}/#{priority})"]
    parts << "Assigned: #{assigned_to_agent.name}" if assigned_to_agent
    parts << "Due: #{due_at.strftime('%Y-%m-%d')}" if due_at
    parts << "Description: #{description.truncate(120)}" if description.present?
    parts.join(" | ")
  end

  private

  def set_completed_at
    if status_changed? && status == "done" && completed_at.nil?
      self.completed_at = Time.current
    elsif status_changed? && status != "done"
      self.completed_at = nil
    end
  end
end
