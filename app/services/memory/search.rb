# frozen_string_literal: true

module Memory
  class Search
    def self.call(agent:, query:, limit: 10, threshold: 0.7)
      new(agent:, query:, limit:, threshold:).call
    end

    def initialize(agent:, query:, limit: 10, threshold: 0.7)
      @agent = agent
      @query = query
      @limit = limit
      @threshold = threshold
    end

    def call
      return ServiceResponse.failure(error: "Query cannot be blank") if @query.blank?

      query_embedding = Memory::Embedding.generate(@query)

      # Fall back to keyword search if embedding generation fails
      unless query_embedding
        results = keyword_fallback
        return ServiceResponse.success(data: { query: @query, results: format_results(results), count: results.length })
      end

      results = MemoryEntry.search_with_threshold(
        embedding: query_embedding,
        agent: @agent,
        threshold: @threshold,
        limit: @limit
      )

      ServiceResponse.success(data: {
        query: @query,
        results: format_results(results),
        count: results.length
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory search failed: #{e.message}")
    end

    private

    def format_results(entries)
      entries.map do |entry|
        similarity = entry.respond_to?(:neighbor_distance) && entry.neighbor_distance
          ? (1 - entry.neighbor_distance).round(4)
          : nil

        {
          id: entry.id,
          content: entry.content,
          similarity: similarity,
          source_type: entry.source_type,
          source_id: entry.source_id,
          metadata: entry.metadata,
          created_at: entry.created_at
        }
      end
    end

    # ILIKE fallback when embedding generation is unavailable
    def keyword_fallback
      keywords = @query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)

      scope = MemoryEntry.where(agent: @agent)

      if keywords.any?
        conditions = keywords.map { "LOWER(content) LIKE ?" }
        values = keywords.map { |kw| "%#{MemoryEntry.sanitize_sql_like(kw)}%" }
        scope.where(conditions.join(" OR "), *values)
      else
        scope
      end.order(created_at: :desc).limit(@limit)
    end
  end
end
