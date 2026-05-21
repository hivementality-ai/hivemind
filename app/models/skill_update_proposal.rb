# frozen_string_literal: true

# An agent-submitted proposal to update an existing skill's content.
# Stored with both original and proposed content for diff rendering.
# Requires admin approval before the skill is modified.
class SkillUpdateProposal < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :skill
  belongs_to :proposed_by_agent, class_name: "Agent"

  validates :proposed_content, presence: true
  validates :rationale, presence: true
  validates :original_content, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending,  -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :recent,   -> { order(created_at: :desc) }
  scope :for_skill, ->(skill) { where(skill: skill) }

  def pending?  = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"

  # Whether the proposed content differs from the current skill content.
  # An agent may have proposed changes that are now stale if another update landed first.
  def stale?
    original_content != skill.content
  end
end
