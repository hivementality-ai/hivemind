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

  scope :actionable, -> { where(status: %w[pending in_progress]) }
  scope :awaiting_review, -> { where(status: "needs_review") }
  scope :completed, -> { where(status: "completed") }
  scope :ordered, -> { order(position: :asc) }

  def dependencies_met?
    return true if depends_on.blank?

    ProjectMilestone.where(id: depends_on).all? { |m| m.status == "completed" }
  end

  def ready_to_start?
    status == "pending" && dependencies_met?
  end

  def auto_approve?
    !requires_approval
  end
end
