# frozen_string_literal: true

module Tools
  class MemorySearchExecutor < BaseExecutor
    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      limit    = (input["limit"] || 10).to_i.clamp(1, 20)
      category = validated_category(input["category"])
      status   = validated_status(input["status"] || "active")

      memories = search_memories(query:, limit:, category:, status:)

      if memories.any?
        output = memories.map.with_index do |mem, i|
          time = mem.created_at.strftime("%Y-%m-%d %H:%M")
          similarity = if mem.respond_to?(:neighbor_distance) && mem.neighbor_distance
            " (#{((1 - mem.neighbor_distance) * 100).round(1)}% match)"
          else
            ""
          end
          meta = "[#{mem.category}/#{mem.status}]"
          "#{i + 1}. [#{time}]#{similarity} #{meta} #{mem.content.truncate(500)}\n   ID: #{mem.id}"
        end.join("\n\n")

        ServiceResponse.success(data: {
          output: "Found #{memories.size} memories:\n\n#{output}",
          exit_code: 0
        })
      else
        filters = []
        filters << "category=#{category}" if category
        filters << "status=#{status}"     if status
        filter_note = filters.any? ? " (#{filters.join(', ')})" : ""

        ServiceResponse.success(data: {
          output: "No memories found matching '#{query}'#{filter_note}.",
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
                          .then { |scope| category ? scope.by_category(category) : scope }
                          .then { |scope| status   ? scope.by_status(status)     : scope }
                          .nearest_neighbors(:embedding, embedding, distance: "cosine")
                          .limit(limit)
      end

      keyword_search(query:, limit:, category:, status:)
    end

    def keyword_search(query:, limit:, category:, status:)
      keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
      scope    = MemoryEntry.where(agent: agent)
      scope    = scope.by_category(category) if category
      scope    = scope.by_status(status)     if status

      if keywords.any?
        conditions = keywords.map { "LOWER(content) LIKE ?" }
        values     = keywords.map { |kw| "%#{MemoryEntry.sanitize_sql_like(kw)}%" }
        scope.where(conditions.join(" OR "), *values)
      else
        scope
      end.order(created_at: :desc).limit(limit)
    end

    def validated_category(value)
      return nil if value.blank?
      return value if MemoryEntry::CATEGORIES.include?(value.to_s)

      nil # silently ignore invalid category — backward compatible
    end

    def validated_status(value)
      return nil if value.blank?
      return value if MemoryEntry::STATUSES.include?(value.to_s)

      "active" # default to active for invalid values
    end
  end
end
