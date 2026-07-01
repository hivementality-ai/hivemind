# frozen_string_literal: true

module Tools
  # Returns memory counts grouped by category and status for the calling agent.
  # Helps agents understand their knowledge inventory at a glance.
  class MemoryStatsExecutor < BaseExecutor
    def call
      return ServiceResponse.failure(error: "Agent context required") unless agent

      base = MemoryEntry.where(agent: agent)

      # Two GROUP BY queries instead of N individual COUNTs
      by_category = base.group(:category).count
      by_status   = base.group(:status).count
      total       = by_status.values.sum

      category_lines = MemoryEntry::CATEGORIES.map do |cat|
        "  #{cat}: #{by_category.fetch(cat, 0)}"
      end

      status_lines = MemoryEntry::STATUSES.map do |st|
        "  #{st}: #{by_status.fetch(st, 0)}"
      end

      output = <<~TEXT.strip
        Memory inventory for #{agent.name}:

        By category:
        #{category_lines.join("\n")}

        By status:
        #{status_lines.join("\n")}

        Total: #{total}
      TEXT

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory stats failed: #{e.message}")
    end
  end
end
