# frozen_string_literal: true

# Seeds tier, tags, and trigger_patterns for built-in skills.
# This runs once at migration time so existing installs pick up the metadata
# without needing a full re-seed.
class SeedSkillTiersAndTags < ActiveRecord::Migration[8.1]
  SKILL_METADATA = {
    "github" => {
      tier: "contextual",
      tags: %w[github git pr pull-request issue ci deploy release branch commit],
      trigger_patterns: [
        "open.*pr", "create.*pull.?request", "merge.*pr",
        "gh\\s", "github", "pull request", "check.*ci",
        "push.*branch", "open.*issue", "close.*issue"
      ]
    },
    "git" => {
      tier: "contextual",
      tags: %w[git commit branch merge rebase checkout stash diff log],
      trigger_patterns: [
        "git\\s", "commit", "branch", "merge conflict",
        "rebase", "stash", "cherry.?pick", "git log", "diff"
      ]
    },
    "docker" => {
      tier: "contextual",
      tags: %w[docker container image dockerfile compose build run],
      trigger_patterns: [
        "docker", "container", "dockerfile", "docker.?compose",
        "build.*image", "run.*container", "docker.*ps"
      ]
    },
    "weather" => {
      tier: "contextual",
      tags: %w[weather forecast temperature rain wind humidity],
      trigger_patterns: [
        "weather", "forecast", "temperature", "rain.*today",
        "wind.*speed", "what.*weather"
      ]
    },
    "trello" => {
      tier: "contextual",
      tags: %w[trello board card list task kanban],
      trigger_patterns: [
        "trello", "board", "kanban card", "move.*card",
        "create.*card", "trello.*list"
      ]
    },
    "notion" => {
      tier: "contextual",
      tags: %w[notion page database block workspace],
      trigger_patterns: [
        "notion", "notion.*page", "notion.*database",
        "create.*notion", "update.*notion"
      ]
    },
    "google-workspace" => {
      tier: "contextual",
      tags: %w[google gmail calendar drive docs sheets slides],
      trigger_patterns: [
        "gmail", "google.*calendar", "google.*drive",
        "send.*email", "calendar.*event", "google.*doc",
        "spreadsheet", "google.*sheet"
      ]
    },
    "summarize" => {
      tier: "contextual",
      tags: %w[summarize summary pdf document article read extract],
      trigger_patterns: [
        "summarize", "summary", "tldr", "read.*pdf",
        "extract.*from", "what.*does.*this.*say", "recap"
      ]
    },
    "ticket-planning" => {
      tier: "contextual",
      tags: %w[ticket task planning breakdown sprint roadmap estimate],
      trigger_patterns: [
        "break.*down", "plan.*task", "create.*ticket", "sprint.*planning",
        "roadmap", "estimate", "user story", "acceptance criteria"
      ]
    },
    "deep_research" => {
      tier: "contextual",
      tags: %w[research investigate deep-dive analysis report findings],
      trigger_patterns: [
        "research", "investigate", "deep.*dive", "find.*information",
        "look.*into", "comprehensive.*report", "analyze.*topic"
      ]
    }
  }.freeze

  def up
    SKILL_METADATA.each do |skill_name, attrs|
      updated = execute(<<~SQL)
        UPDATE skills
        SET tier              = #{quote(attrs[:tier])},
            tags              = ARRAY[#{attrs[:tags].map { |t| quote(t) }.join(", ")}]::text[],
            trigger_patterns  = ARRAY[#{attrs[:trigger_patterns].map { |p| quote(p) }.join(", ")}]::text[]
        WHERE name = #{quote(skill_name)}
      SQL

      say "  Updated skill '#{skill_name}' (tier=#{attrs[:tier]}, #{attrs[:tags].size} tags, #{attrs[:trigger_patterns].size} patterns)"
    end
  end

  def down
    execute("UPDATE skills SET tier = 'manual', tags = '{}', trigger_patterns = '{}' WHERE builtin = true")
  end

  private

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
