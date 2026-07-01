# frozen_string_literal: true

module Tools
  # Retrieval tool for the document knowledge base. Embeds the query with the
  # same adapter memory uses, then runs pgvector cosine nearest-neighbors over
  # KnowledgeChunk scoped to the agent. Modeled on MemorySearchExecutor.
  class KnowledgeSearchExecutor < BaseExecutor
    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?
      return ServiceResponse.failure(error: "Agent context required") unless agent

      limit  = (input["limit"] || 5).to_i.clamp(1, 20)
      chunks = search_chunks(query:, limit:)

      if chunks.any?
        output = chunks.map.with_index do |chunk, i|
          match = if chunk.respond_to?(:neighbor_distance) && chunk.neighbor_distance
            " (#{((1 - chunk.neighbor_distance) * 100).round(1)}% match)"
          else
            ""
          end
          title = chunk.knowledge_document.title
          "#{i + 1}.#{match} [#{title} ##{chunk.position}] #{chunk.content.truncate(500)}"
        end.join("\n\n")

        ServiceResponse.success(data: { output: "Found #{chunks.size} chunks:\n\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No knowledge base results for '#{query}'.", exit_code: 0 })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Knowledge search failed: #{e.message}")
    end

    private

    def search_chunks(query:, limit:)
      embedding = Memory::Embedding.generate_query(query)
      return KnowledgeChunk.none unless embedding

      KnowledgeChunk.search_similar(embedding: embedding, agent: agent, limit: limit)
    end
  end
end
