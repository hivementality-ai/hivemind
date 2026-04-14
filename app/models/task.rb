# frozen_string_literal: true

class Task < ApplicationRecord
  STATUSES   = %w[backlog todo in_progress review done].freeze
  PRIORITIES = %w[low medium high urgent].freeze

  belongs_to :created_by_agent, class_name: "Agent", optional: true
  belongs_to :assigned_to_agent, class_name: "Agent", optional: true
  belongs_to :task_template, optional: true

  has_many :task_hooks, dependent: :destroy
  has_many :task_events, dependent: :destroy
  has_many :task_dependencies, dependent: :destroy
  has_many :blocking_tasks, through: :task_dependencies, source: :depends_on
  has_many :inverse_dependencies, class_name: "TaskDependency", foreign_key: :depends_on_id,
           dependent: :destroy, inverse_of: :depends_on
  has_many :dependent_tasks, through: :inverse_dependencies, source: :task

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

  # Returns hooks for a given status transition and trigger direction.
  # Task-level hooks take precedence; falls back to template hooks.
  def effective_hooks_for(status, trigger)
    direct = task_hooks.enabled.for_status(status).where(trigger: trigger).ordered
    return direct if direct.any?
    return TaskHook.none unless task_template

    task_template.task_hooks.enabled.for_status(status).where(trigger: trigger).ordered
  end

  # Are all blocking dependencies completed?
  def dependencies_met?
    return true unless task_dependencies.exists?

    blocking_tasks.where.not(status: "done").none?
  end

  def blocked_by_dependencies?
    task_dependencies.exists? && !dependencies_met?
  end

  def checklist_complete?
    return true if checklist.blank?

    checklist.all? { |item| item["checked"] == true }
  end

  def toggle_checklist_item(index)
    return false if checklist.blank? || index < 0 || index >= checklist.size

    checklist[index]["checked"] = !checklist[index]["checked"]
    save!
  end

  def add_checklist_item(title)
    self.checklist = (checklist || []) + [ { "title" => title, "checked" => false } ]
    save!
  end

  def apply_template!(template)
    self.task_template = template
    self.priority = template.default_priority if priority == "medium" && template.default_priority != "medium"
    self.metadata = (metadata || {}).merge(template.default_metadata) if template.default_metadata.present?
    self
  end

  def add_comment(author_name:, body:)
    entry = {
      "author"     => author_name,
      "body"       => body,
      "created_at" => Time.current.iso8601
    }
    self.comments = (comments || []) + [ entry ]
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
    parts = [ "[##{id}] #{title} (#{status}/#{priority})" ]
    parts << "Assigned: #{assigned_to_agent.name}" if assigned_to_agent
    parts << "Due: #{due_at.strftime('%Y-%m-%d')}" if due_at
    parts << "Blocked" if blocked_by_dependencies?
    parts << "Checklist: #{checklist.count { |i| i['checked'] }}/#{checklist.size}" if checklist.present?
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
