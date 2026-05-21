# frozen_string_literal: true

module Tools
  # Retrieves the agent's structured user model — a canonical view of everything
  # the agent knows about how the user likes to work. Pulls all active
  # user_preference memories, groups them by inferred section, and returns a
  # formatted document the agent can reason over in a single call.
  #
  # Sections (inferred from content keywords):
  #   Communication Style  — tone, format, verbosity, writing preferences
  #   Workflow Preferences — tools, git flow, PR rules, deployment habits
  #   Domain Expertise     — technologies, stacks, languages the user knows well
  #   Recurring Patterns   — habits and rules the agent has learned over time
  #   Other Preferences    — everything that doesn't fit the above
  class UserModelExecutor < BaseExecutor
    SECTIONS = {
      "Communication Style"  => %w[tone format verbose concise writing style message response brief
                                   detailed bullet prose markdown emoji language communication],
      "Workflow Preferences" => %w[git branch commit pr push merge deploy workflow pipeline ci cd
                                   test review task sprint agile jira trello ticket worktree],
      "Domain Expertise"     => %w[ruby rails python javascript typescript react node java go rust
                                   aws gcp azure docker kubernetes postgres mysql redis elasticsearch
                                   framework stack language library technology],
      "Recurring Patterns"   => %w[always never prefer avoid rule pattern habit strict enforce
                                   require must should don't do not zero tolerance]
    }.freeze

    OTHER_SECTION = "Other Preferences"

    def call
      return ServiceResponse.failure(error: "Agent context required") unless agent

      preferences = load_preferences
      return empty_model_response if preferences.empty?

      ServiceResponse.success(data: {
        output: format_user_model(preferences),
        exit_code: 0
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to load user model: #{e.message}")
    end

    private

    def load_preferences
      MemoryEntry
        .where(agent: agent, category: "user_preference", status: "active")
        .order(created_at: :asc)
    end

    def format_user_model(preferences)
      grouped = group_by_section(preferences)
      total   = preferences.size

      lines = [ "## User Model (#{total} preferences)\n" ]

      SECTIONS.each_key do |section|
        entries = grouped[section]
        next if entries.blank?

        lines << "### #{section}"
        entries.each { |entry| lines << format_entry(entry) }
        lines << ""
      end

      other = grouped[OTHER_SECTION]
      if other.present?
        lines << "### #{OTHER_SECTION}"
        other.each { |entry| lines << format_entry(entry) }
        lines << ""
      end

      lines << "_Use `memory_search` with `category: user_preference` to query specific preferences. " \
               "Use `memory_update` with a memory ID to revise or archive stale entries._"

      lines.join("\n")
    end

    def format_entry(entry)
      date = entry.updated_at.strftime("%Y-%m-%d")
      "- [ID:#{entry.id}] #{entry.content.truncate(300)} _(#{date})_"
    end

    def group_by_section(preferences)
      grouped = Hash.new { |h, k| h[k] = [] }

      preferences.each do |entry|
        section = classify_section(entry.content)
        grouped[section] << entry
      end

      grouped
    end

    def classify_section(content)
      lower = content.downcase

      SECTIONS.each do |section, keywords|
        return section if keywords.any? { |kw| lower.include?(kw) }
      end

      OTHER_SECTION
    end

    def empty_model_response
      ServiceResponse.success(data: {
        output: "No user preferences recorded yet.\n\n" \
                "Use `memory_store` with `category: user_preference` to start building your user model. " \
                "Or run `user_model_populate` to auto-scan existing memories and extract preferences.",
        exit_code: 0
      })
    end
  end
end
