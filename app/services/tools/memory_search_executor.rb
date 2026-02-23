# frozen_string_literal: true

module Tools
  class MemorySearchExecutor < BaseExecutor
    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      limit = (input["limit"] || 10).to_i.clamp(1, 20)

      # Try semantic search first, fall back to keyword
      memories = search_memories(query:, limit:)

      if memories.any?
        output = memories.map.with_index do |mem, i|
          time = mem.created_at.strftime("%Y-%m-%d %H:%M")
          similarity = mem.respond_to?(:neighbor_distance) && mem.neighbor_distance
            ? " (#{((1 - mem.neighbor_distance) * 100).round(1)}% match)"
            : ""
          "#{i + 1}. [#{time}]#{similarity} #{mem.content.truncate(500)}"
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

      # Attempt vector search
      embedding = Memory::Embedding.generate(query)
      if embedding
        return MemoryEntry.where(agent: agent)
                          .nearest_neighbors(:embedding, embedding, distance: "cosine")
                          .limit(limit)
      end

      # Keyword fallback
      keyword_search(query:, limit:)
    end

    def keyword_search(query:, limit:)
      keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
      scope = MemoryEntry.where(agent: agent)

      if keywords.any?
        conditions = keywords.map { "LOWER(content) LIKE ?" }
        values = keywords.map { |kw| "%#{MemoryEntry.sanitize_sql_like(kw)}%" }
        scope.where(conditions.join(" OR "), *values)
      else
        scope
      end.order(created_at: :desc).limit(limit)
    end
  end
end
