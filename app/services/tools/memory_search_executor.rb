# frozen_string_literal: true

module Tools
  class MemorySearchExecutor < BaseExecutor
    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      limit    = (input["limit"] || 10).to_i.clamp(1, 20)
      category = input["category"].presence
      status   = input["status"].presence || "active"

      if category.present? && !MemoryEntry::CATEGORIES.include?(category)
        return ServiceResponse.failure(
          error: "Invalid category '#{category}'. Valid values: #{MemoryEntry::CATEGORIES.join(', ')}"
        )
      end

      unless MemoryEntry::STATUSES.include?(status)
        return ServiceResponse.failure(
          error: "Invalid status '#{status}'. Valid values: #{MemoryEntry::STATUSES.join(', ')}"
        )
      end

      memories = search_memories(query:, limit:, category:, status:)

      if memories.any?
        output = memories.map.with_index do |mem, i|
          time       = mem.created_at.strftime("%Y-%m-%d %H:%M")
          similarity = if mem.respond_to?(:neighbor_distance) && mem.neighbor_distance
                        " (#{((1 - mem.neighbor_distance) * 100).round(1)}% match)"
                       else
                        ""
                       end
          category_tag = "[#{mem.category}]" if mem.respond_to?(:category) && mem.category.present?
          status_tag   = mem.status != "active" ? " [#{mem.status}]" : ""
          "[#{time}]#{similarity}#{status_tag} #{category_tag} #{mem.content.truncate(500)}"
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

    def search_memories(query:, limit:, category:, status:)
      return MemoryEntry.none unless agent

      embedding = Memory::Embedding.generate_query(query)
      if embedding
        return MemoryEntry.where(agent: agent)
                          .then { |scope| status.present? ? scope.where(status: status) : scope }
                          .then { |scope| category.present? ? scope.where(category: category) : scope }
                          .nearest_neighbors(:embedding, embedding, distance: "cosine")
                          .limit(limit)
      end

      keyword_search(query:, limit:, category:, status:)
    end

    def keyword_search(query:, limit:, category:, status:)
      keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
      scope    = MemoryEntry.where(agent: agent)
      scope    = scope.where(status: status) if status.present?
      scope    = scope.where(category: category) if category.present?

      if keywords.any?
        conditions = keywords.map { "LOWER(content) LIKE ?" }
        values     = keywords.map { |kw| "%#{MemoryEntry.sanitize_sql_like(kw)}%" }
        scope.where(conditions.join(" OR "), *values)
      else
        scope
      end.order(created_at: :desc).limit(limit)
    end
  end
end
