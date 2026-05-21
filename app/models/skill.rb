# frozen_string_literal: true

require "digest"

class Skill < ApplicationRecord
  CATEGORIES = %w[coding productivity automation messaging lifestyle utilities integrations].freeze
  TIERS = %w[core contextual manual].freeze
  PROPOSAL_STATUSES = %w[pending approved rejected].freeze

  has_many :agent_skills, dependent: :destroy
  has_many :agents, through: :agent_skills
  has_many :skill_tools, dependent: :destroy
  has_many :tools, through: :skill_tools
  has_many :skill_load_events, dependent: :destroy

  belongs_to :proposing_agent, class_name: "Agent", foreign_key: "proposed_by_agent_id", optional: true

  validates :name, presence: true, uniqueness: true
  validates :content, presence: true
  validates :summary, presence: true, length: { maximum: 150 }
  validates :tier, inclusion: { in: TIERS }
  validates :proposal_status, inclusion: { in: PROPOSAL_STATUSES }, allow_nil: true

  before_save :compute_checksum, if: :content_changed?

  scope :enabled, -> { where(enabled: true) }
  scope :builtin, -> { where(builtin: true) }
  scope :custom, -> { where(builtin: false) }
  scope :core_tier, -> { where(tier: "core") }
  scope :contextual_tier, -> { where(tier: "contextual") }
  scope :manual_tier, -> { where(tier: "manual") }
  scope :with_tag, ->(tag) { where("? = ANY(tags)", tag) }
  scope :agent_authored, -> { where(source: "agent") }
  scope :pending_proposals, -> { agent_authored.where(proposal_status: "pending") }
  scope :approved_proposals, -> { agent_authored.where(proposal_status: "approved") }
  scope :rejected_proposals, -> { agent_authored.where(proposal_status: "rejected") }

  def proposal_pending?
    proposal_status == "pending"
  end

  def proposal_approved?
    proposal_status == "approved"
  end

  def proposal_rejected?
    proposal_status == "rejected"
  end

  # Parse OpenClaw-compatible SKILL.md content
  def self.from_skill_md(text)
    frontmatter, body = parse_frontmatter(text)

    new(
      name: frontmatter["name"],
      description: frontmatter["description"],
      summary: (frontmatter["summary"] || frontmatter["description"].to_s).truncate(150),
      content: body.strip,
      category: frontmatter.dig("metadata", "openclaw", "category") || frontmatter["category"]
    )
  end

  # Export as OpenClaw-compatible SKILL.md
  def to_skill_md
    lines = [ "---" ]
    lines << "name: #{name}"
    lines << "description: #{description}" if description.present?
    lines << "category: #{category}" if category.present?
    lines << "---"
    lines << ""
    lines << content
    lines.join("\n")
  end

  def security_status
    security_scan_result.dig("status") || "unscanned"
  end

  def security_clean?
    security_status == "clean"
  end

  def security_blocked?
    security_status == "blocked"
  end

  def scan_security!
    result = SkillSecurityScanner.call(content: content, name: name)
    update!(security_scan_result: result.data) if result.success?
    result
  end

  # Returns the tags array, always as strings.
  def tags
    self[:tags] || []
  end

  # Returns the trigger_patterns array, always as strings.
  def trigger_patterns
    self[:trigger_patterns] || []
  end

  # Computes a relevance score (0.0–1.0) for this skill against a given text context.
  # Checks both tags and trigger_patterns against the context.
  def relevance_score_for(context_text)
    return 0.0 if context_text.blank?
    return 0.0 if tags.empty? && trigger_patterns.empty?

    Skills::RelevanceScorer.score(skill: self, context: context_text)
  end

  private

  def compute_checksum
    self.checksum = Digest::SHA256.hexdigest(content)
  end

  private_class_method def self.parse_frontmatter(text)
    if text.strip.start_with?("---")
      parts = text.strip.split(/^---\s*$/, 3)
      if parts.length >= 3
        frontmatter = YAML.safe_load(parts[1]) || {}
        return [ frontmatter, parts[2] ]
      end
    end
    [ {}, text ]
  end
end
