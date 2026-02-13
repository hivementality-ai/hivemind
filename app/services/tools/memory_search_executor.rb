# frozen_string_literal: true

module Tools
  class MemorySearchExecutor < BaseExecutor
    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      limit = (input["limit"] || 10).to_i.clamp(1, 20)

      # Search agent's memories via keyword matching
      memories = search_memories(query:, limit:)

      if memories.any?
        output = memories.map.with_index do |mem, i|
          time = mem.created_at.strftime("%Y-%m-%d %H:%M")
          "#{i + 1}. [#{time}] #{mem.content.truncate(500)}"
        end.join("\n\n")

        ServiceResponse.success(data: {
          output: "Found #{memories.size} memories:\n\n#{output}",
          exit_code: 0
        })
      else
        ServiceResponse.success(data: {
          output: "No memories found matching '#{query}'.",
          exit_code: 0
        })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory search failed: #{e.message}")
    end

    private

    def search_memories(query:, limit:)
      return MemoryEntry.none unless agent

      # Split query into keywords for ILIKE search
      keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
      return agent_memories.order(created_at: :desc).limit(limit) if keywords.empty?

      # Search with OR across keywords
      conditions = keywords.map { "LOWER(content) LIKE ?" }
      values = keywords.map { |kw| "%#{MemoryEntry.sanitize_sql_like(kw)}%" }

      matched = agent_memories
        .where(conditions.join(" OR "), *values)
        .order(created_at: :desc)
        .limit(limit)

      # If not enough results, pad with recent memories
      if matched.size < limit
        recent = agent_memories
          .where.not(id: matched.map(&:id))
          .order(created_at: :desc)
          .limit(limit - matched.size)
        matched + recent
      else
        matched
      end
    end

    def agent_memories
      MemoryEntry.where(agent: agent)
    end
  end
end
