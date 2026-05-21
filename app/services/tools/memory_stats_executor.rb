# frozen_string_literal: true

module Tools
  # Returns memory counts grouped by category and status, scoped to the calling agent.
  class MemoryStatsExecutor < BaseExecutor
    def call
      return ServiceResponse.failure(error: "No agent context") unless agent

      by_category = MemoryEntry
        .where(agent: agent)
        .group(:category)
        .count

      by_status = MemoryEntry
        .where(agent: agent)
        .group(:status)
        .count

      by_category_and_status = MemoryEntry
        .where(agent: agent)
        .group(:category, :status)
        .count

      total = MemoryEntry.where(agent: agent).count

      output = format_stats(total, by_category, by_status, by_category_and_status)

      ServiceResponse.success(data: { output:, exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory stats failed: #{e.message}")
    end

    private

    def format_stats(total, by_category, by_status, by_category_and_status)
      lines = [ "## Memory Inventory (#{total} total)\n" ]

      lines << "### By Status"
      MemoryEntry::STATUSES.each do |s|
        count = by_status[s] || 0
        lines << "  #{s}: #{count}"
      end

      lines << "\n### By Category"
      MemoryEntry::CATEGORIES.each do |cat|
        count = by_category[cat] || 0
        next if count.zero?

        lines << "  #{cat}: #{count}"
        # Break down by status within this category
        MemoryEntry::STATUSES.each do |s|
          sub = by_category_and_status[[cat, s]] || 0
          lines << "    #{s}: #{sub}" if sub > 0
        end
      end

      lines.join("\n")
    end
  end
end
