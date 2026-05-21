# frozen_string_literal: true

module Tools
  # Returns memory counts grouped by category and status for the calling agent.
  # Helps agents understand their knowledge inventory at a glance.
  class MemoryStatsExecutor < BaseExecutor
    def call
      return ServiceResponse.failure(error: "Agent context required") unless agent

      base = MemoryEntry.where(agent: agent)

      by_category = MemoryEntry::CATEGORIES.map do |cat|
        count = base.where(category: cat).count
        "  #{cat}: #{count}"
      end

      by_status = MemoryEntry::STATUSES.map do |st|
        count = base.where(status: st).count
        "  #{st}: #{count}"
      end

      total = base.count

      output = <<~TEXT.strip
        Memory inventory for #{agent.name}:

        By category:
        #{by_category.join("\n")}

        By status:
        #{by_status.join("\n")}

        Total: #{total}
      TEXT

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory stats failed: #{e.message}")
    end
  end
end
