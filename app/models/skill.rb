# frozen_string_literal: true

class Skill < ApplicationRecord
  has_many :agent_skills, dependent: :destroy
  has_many :agents, through: :agent_skills
  has_many :skill_tools, dependent: :destroy
  has_many :tools, through: :skill_tools

  # Individual skill content limit (~500 tokens). Skills are injected into every
  # API call as part of the system prompt, so bloated skills burn tokens fast.
  MAX_CONTENT_CHARS = 2000

  validates :name, presence: true, uniqueness: true
  validates :content, presence: true, length: {
    maximum: MAX_CONTENT_CHARS,
    message: "is too long (max %{count} characters / ~500 tokens). Keep skills concise — agents already know how to use most tools. Just provide environment-specific details."
  }

  scope :enabled, -> { where(enabled: true) }
  scope :builtin, -> { where(builtin: true) }
  scope :custom, -> { where(builtin: false) }

  CATEGORIES = %w[coding productivity automation messaging lifestyle utilities integrations].freeze

  # Parse OpenClaw-compatible SKILL.md content
  def self.from_skill_md(text)
    frontmatter, body = parse_frontmatter(text)

    new(
      name: frontmatter["name"],
      description: frontmatter["description"],
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
