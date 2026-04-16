# frozen_string_literal: true

class Task < ApplicationRecord
  STATUSES   = %w[backlog todo in_progress review done].freeze
  PRIORITIES = %w[low medium high urgent].freeze

  belongs_to :created_by_agent, class_name: "Agent", optional: true
  belongs_to :assigned_to_agent, class_name: "Agent", optional: true
  belongs_to :task_template, optional: true
  belongs_to :project, optional: true
  belongs_to :project_milestone, optional: true
  belongs_to :session, optional: true

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

  scope :open,         -> { where.not(status: "done") }
  scope :done,         -> { where(status: "done") }
  scope :not_archived, -> { where(archived_at: nil) }
  scope :archived,     -> { where.not(archived_at: nil) }
  scope :for_agent,   ->(agent)   { where(assigned_to_agent: agent) }
  scope :for_project, ->(project) { where(project: project) }
  scope :by_status,  ->(s) { where(status: s) }
  scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END")) }
  scope :recent,     -> { order(created_at: :desc) }

  # Returns hooks for a given status transition and trigger direction.
  # Precedence: task-level > template-level > team-level (defaults).
  def effective_hooks_for(status, trigger)
    direct = task_hooks.enabled.for_status(status).where(trigger: trigger).ordered
    return direct if direct.any?

    if task_template
      template_hooks = task_template.task_hooks.enabled.for_status(status).where(trigger: trigger).ordered
      return template_hooks if template_hooks.any?
    end

    team = resolved_team
    return TaskHook.none unless team

    team.task_hooks.enabled.for_status(status).where(trigger: trigger).ordered
  end

  # Resolve team through agent associations.
  def resolved_team
    (assigned_to_agent || created_by_agent)&.team
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

  # ─── Artifacts ───────────────────────────────────────────────────
  ARTIFACT_TYPES = %w[code document report data image link other].freeze

  def add_artifact(title:, content: nil, type: "document", metadata: {}, created_by: nil)
    artifact_type = ARTIFACT_TYPES.include?(type) ? type : "document"
    entry = {
      "id"         => SecureRandom.uuid,
      "type"       => artifact_type,
      "title"      => title,
      "content"    => content,
      "metadata"   => metadata,
      "created_by" => created_by,
      "created_at" => Time.current.iso8601
    }.compact
    self.artifacts = (artifacts || []) + [ entry ]
    save!
    entry
  end

  def remove_artifact(artifact_id)
    return false if artifacts.blank?

    original_size = artifacts.size
    self.artifacts = artifacts.reject { |a| a["id"] == artifact_id }
    return false if artifacts.size == original_size

    save!
    true
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

  def archive!
    raise ArgumentError, "only done tasks can be archived" unless status == "done"

    update!(archived_at: Time.current)
  end

  def archived?
    archived_at.present?
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
    parts << "Project: #{project.title}" if project
    parts << "Milestone: #{project_milestone.title}" if project_milestone
    parts << "Blocked" if blocked_by_dependencies?
    parts << "Checklist: #{checklist.count { |i| i['checked'] }}/#{checklist.size}" if checklist.present?
    parts << "Artifacts: #{artifacts.size}" if artifacts.present?
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
