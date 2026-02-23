# frozen_string_literal: true

module Sessions
  class Chat
    def self.call(...)
      new(...).call
    end

    def initialize(session:, message:, stream: false, agent: nil, &on_chunk)
      @session = session
      @message = message
      @stream = stream
      @on_chunk = on_chunk
    end

    def call
      agent = @session.agent

      # 1. Append user message to transcript
      @session.append_transcript({ "role" => "user", "content" => @message })

      # 2. Resolve the provider adapter
      resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent:)
      return resolver unless resolver.success?

      adapter = resolver.data[:adapter]

      # 3. Recall relevant memories
      memories = recall_memories(agent:, query: @message)

      # 4. Build messages array from transcript + memories
      messages = build_messages(agent:, memories:)

      # 5. Call the LLM
      options = { model: agent.llm_model }

      if @stream && @on_chunk
        response = adapter.chat(messages:, options:) do |chunk|
          @on_chunk.call(chunk)
        end
      else
        response = adapter.chat(messages:, options:)
      end

      return response unless response.success?

      content = response.data[:content]
      usage = response.data[:usage] || {}

      # 6. Append assistant response to transcript
      @session.append_transcript({ "role" => "assistant", "content" => content })

      # 7. Update token counts
      input_tokens = usage[:input_tokens] || 0
      output_tokens = usage[:output_tokens] || 0
      @session.update!(
        input_tokens: @session.input_tokens + input_tokens,
        output_tokens: @session.output_tokens + output_tokens,
        total_tokens: @session.total_tokens + input_tokens + output_tokens
      )

      # 8. Record usage for budgets/analytics
      record_usage(agent:, input_tokens:, output_tokens:)

      # 9. Auto-store memory from this exchange (async-friendly)
      store_memory(agent:, user_message: @message, assistant_response: content)

      ServiceResponse.success(data: { content:, usage: })
    rescue StandardError => e
      Rails.logger.error("[Sessions::Chat] Error: #{e.message}")
      ServiceResponse.failure(error: e.message)
    end

    private

    # ----- Memory Recall -----

    def recall_memories(agent:, query:)
      query_embedding = Memory::Embedding.generate(query)

      if query_embedding
        # Semantic search via pgvector
        semantic = MemoryEntry.where(agent: agent)
                              .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
                              .limit(5)
      else
        # Keyword fallback if embedding generation fails
        keywords = query.downcase.gsub(/[^a-z0-9\s]/, "").split.reject { |w| w.length < 4 }.first(3)
        semantic = if keywords.any?
                     conditions = keywords.map { "LOWER(content) LIKE ?" }
                     values = keywords.map { |kw| "%#{MemoryEntry.sanitize_sql_like(kw)}%" }
                     MemoryEntry.where(agent: agent).where(conditions.join(" OR "), *values)
                                .order(created_at: :desc).limit(5)
                   else
                     MemoryEntry.none
                   end
      end

      # Also grab the most recent memories regardless of relevance
      recent = MemoryEntry.where(agent: agent)
                          .order(created_at: :desc)
                          .limit(3)

      # Combine, dedupe, limit
      (semantic.to_a + recent.to_a).uniq(&:id).first(5)
    rescue StandardError => e
      Rails.logger.warn("[Sessions::Chat] Memory recall failed: #{e.message}")
      []
    end

    # ----- Memory Storage -----

    def store_memory(agent:, user_message:, assistant_response:)
      # Only store meaningful exchanges (skip short greetings)
      return if user_message.length < 20 && assistant_response.length < 50

      content = "User asked: #{user_message.truncate(200)}\nAgent responded: #{assistant_response.truncate(500)}"

      # Create entry without embedding; async job will generate it
      entry = MemoryEntry.create(
        agent:,
        content:,
        source: @session,
        metadata: {
          session_id: @session.id,
          turn: @session.transcript_size,
          stored_at: Time.current.iso8601
        }
      )

      MemoryEmbeddingJob.perform_later(entry.id) if entry.persisted?
    rescue StandardError => e
      Rails.logger.warn("[Sessions::Chat] Memory storage failed: #{e.message}")
    end

    # ----- Message Building -----

    def build_messages(agent:, memories: [])
      messages = []

      # System prompt with memory context
      system_content = build_system_prompt(agent:, memories:)
      messages << { role: "system", content: system_content } if system_content.present?

      # Conversation history from transcript (last 50 messages to stay within context)
      transcript = @session.transcript || []
      transcript.last(50).each do |entry|
        messages << { role: entry["role"], content: entry["content"] }
      end

      messages
    end

    def build_system_prompt(agent:, memories: [])
      parts = []

      # Core identity / soul
      parts << agent.full_system_prompt if agent.full_system_prompt.present?

      # Inject relevant memories
      if memories.any?
        memory_text = memories.map { |m| "- #{m.content}" }.join("\n")
        parts << <<~MEMORY
          ## Your Memories
          You have the following relevant memories from past interactions:
          #{memory_text}

          Use these memories naturally in conversation when relevant. Don't mention that you're "recalling memories" — just use the knowledge.
        MEMORY
      end

      parts.join("\n\n")
    end

    # ----- Usage Tracking -----

    def record_usage(agent:, input_tokens:, output_tokens:)
      UsageRecord.create(
        agent:,
        session: @session,
        provider: agent.model_provider,
        llm_model: agent.llm_model,
        input_tokens:,
        output_tokens:,
        cost_cents: CostEstimator.estimate(model: agent.llm_model, input_tokens:, output_tokens:)
      )
    rescue StandardError => e
      Rails.logger.warn("[Sessions::Chat] Failed to record usage: #{e.message}")
    end
  end
end
