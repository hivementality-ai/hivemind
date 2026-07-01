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
  has_many :skill_versions, dependent: :destroy
  has_many :skill_update_proposals, dependent: :destroy

  belongs_to :proposing_agent, class_name: "Agent", foreign_key: "proposed_by_agent_id", optional: true

  validates :name, presence: true, uniqueness: true
  validates :content, presence: true
  validates :summary, presence: true, length: { maximum: 150 }
  validates :tier, inclusion: { in: TIERS }
  validates :proposal_status, inclusion: { in: PROPOSAL_STATUSES }, allow_nil: true

  before_save :compute_checksum, if: :content_changed?
  after_create :snapshot_initial_version
  after_update :snapshot_updated_version, if: :saved_change_to_content?

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

  # Returns pending update proposals (distinct from new-skill proposals).
  def pending_update_proposals
    skill_update_proposals.pending
  end

  # Parse SKILL.md content. Compatible with both OpenClaw and the agentskills.io
  # open standard (YAML frontmatter: name + description required, plus optional
  # license, tags, version, source_url, or a nested metadata block).
  def self.from_skill_md(text)
    frontmatter, body = parse_frontmatter(text)
    meta = frontmatter["metadata"].is_a?(Hash) ? frontmatter["metadata"] : {}

    tags = frontmatter["tags"] || meta["tags"]
    tags = tags.to_s.split(/[,\s]+/) if tags.is_a?(String)

    extra_metadata = {}
    %w[license version author].each do |k|
      v = frontmatter[k] || meta[k]
      extra_metadata[k] = v if v.present?
    end

    new(
      name: frontmatter["name"],
      description: frontmatter["description"],
      summary: (frontmatter["summary"] || frontmatter["description"].to_s).truncate(150),
      content: body.strip,
      category: meta.dig("openclaw", "category") || frontmatter["category"] || meta["category"],
      tags: Array(tags).map(&:to_s).reject(&:blank?),
      source_url: frontmatter["source_url"] || meta["source_url"],
      metadata: extra_metadata
    )
  end

  # Export as SKILL.md (agentskills.io / OpenClaw compatible). Built via YAML so
  # values with colons/special chars are quoted correctly; extra fields are
  # emitted only when present.
  def to_skill_md
    frontmatter = { "name" => name }
    frontmatter["description"] = description if description.present?
    frontmatter["category"] = category if category.present?
    frontmatter["tags"] = tags if tags.any?
    frontmatter["license"] = metadata["license"] if metadata["license"].present?
    frontmatter["version"] = metadata["version"] if metadata["version"].present?
    frontmatter["source_url"] = source_url if source_url.present?

    "#{YAML.dump(frontmatter)}---\n\n#{content}"
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

  def snapshot_initial_version
    SkillVersion.snapshot!(
      skill: self,
      change_source: source == "agent" ? "agent_update" : "manual",
      changed_by_agent_id: proposed_by_agent_id,
      change_summary: "Initial version"
    )
  rescue StandardError => e
    Rails.logger.error("[Skill] Failed to snapshot initial version for '#{name}': #{e.message}")
  end

  def snapshot_updated_version
    # Skip if this update is being driven by the UpdateApprover — it handles snapshotting itself
    # to attach the proposal link. We detect this via the @skip_auto_snapshot flag.
    return if @skip_auto_snapshot

    SkillVersion.snapshot!(
      skill: self,
      change_source: "manual",
      change_summary: "Content updated"
    )
  rescue StandardError => e
    Rails.logger.error("[Skill] Failed to snapshot updated version for '#{name}': #{e.message}")
  end

  # Called by Skills::UpdateApprover to suppress the auto-snapshot so it can
  # create a richer version record (with proposal linkage, agent attribution, etc.).
  def skip_auto_snapshot!
    @skip_auto_snapshot = true
  end

  public :skip_auto_snapshot!

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
