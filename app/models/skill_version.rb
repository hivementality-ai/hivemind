# frozen_string_literal: true

require "digest"

# Immutable snapshot of a skill's content at a point in time.
# Created whenever a skill's content is saved (initial creation or approved update).
class SkillVersion < ApplicationRecord
  CHANGE_SOURCES = %w[manual agent_update import rollback].freeze

  belongs_to :skill
  belongs_to :proposing_agent, class_name: "Agent", foreign_key: "changed_by_agent_id", optional: true

  validates :version_number, presence: true, uniqueness: { scope: :skill_id }
  validates :content, presence: true
  validates :checksum, presence: true
  validates :change_source, inclusion: { in: CHANGE_SOURCES }

  scope :for_skill, ->(skill) { where(skill: skill) }
  scope :chronological, -> { order(version_number: :asc) }
  scope :reverse_chronological, -> { order(version_number: :desc) }

  before_validation :compute_checksum, if: :content_changed?

  # Snapshot the current content of a skill as a new version.
  # Returns the created SkillVersion.
  def self.snapshot!(skill:, change_source:, changed_by_user_id: nil, changed_by_agent_id: nil,
                     change_summary: nil, update_proposal_id: nil)
    next_version = (for_skill(skill).maximum(:version_number) || 0) + 1

    create!(
      skill: skill,
      version_number: next_version,
      content: skill.content,
      checksum: Digest::SHA256.hexdigest(skill.content),
      change_source: change_source,
      changed_by_user_id: changed_by_user_id,
      changed_by_agent_id: changed_by_agent_id,
      change_summary: change_summary,
      update_proposal_id: update_proposal_id
    )
  end

  private

  def compute_checksum
    self.checksum = Digest::SHA256.hexdigest(content) if content.present?
  end
end
