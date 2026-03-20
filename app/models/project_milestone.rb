# frozen_string_literal: true

class ProjectMilestone < ApplicationRecord
  belongs_to :project
  belongs_to :agent, optional: true
  belongs_to :session, optional: true
  has_many :events, class_name: "ProjectEvent", dependent: :nullify

  validates :title, presence: true
  validates :status, inclusion: {
    in: %w[pending in_progress needs_review approved completed blocked skipped]
  }
  validate :dependencies_within_same_project, if: -> { depends_on.present? }

  scope :actionable, -> { where(status: %w[pending in_progress]) }
  scope :awaiting_review, -> { where(status: "needs_review") }
  scope :completed, -> { where(status: "completed") }
  scope :ordered, -> { order(position: :asc) }

  def dependencies_met?
    return true if depends_on.blank?

    # Verify ALL dependency IDs exist and are completed
    completed_count = ProjectMilestone.where(id: depends_on, status: "completed").count
    completed_count == depends_on.size
  end

  def ready_to_start?
    status == "pending" && dependencies_met?
  end

  def auto_approve?
    !requires_approval
  end

  private

  def dependencies_within_same_project
    return if depends_on.blank? || project_id.blank?

    invalid = ProjectMilestone.where(id: depends_on).where.not(project_id: project_id)
    errors.add(:depends_on, "contains milestones from a different project") if invalid.any?
  end
end
