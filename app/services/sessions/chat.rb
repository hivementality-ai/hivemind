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

      # 3. Build memory context (preferences + relevant + recent)
      memory_result = Memory::ContextBuilder.call(agent:, query: @message)

      # 4. Build messages array from transcript + memory context
      messages = build_messages(agent:, memory_context: memory_result[:context])

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

      # 9. Auto-store raw memory from this exchange
      store_memory(agent:, user_message: @message, assistant_response: content)

      # 10. Extract facts/preferences in background (real-time learning)
      MemoryExtractionJob.perform_later(agent.id, @message, content)

      # 11. Trigger consolidation for longer sessions (every 20 turns)
      maybe_consolidate

      ServiceResponse.success(data: { content:, usage: })
    rescue StandardError => e
      Rails.logger.error("[Sessions::Chat] Error: #{e.message}")
      ServiceResponse.failure(error: e.message)
    end

    private

    # ----- Memory Storage -----

    def store_memory(agent:, user_message:, assistant_response:)
      # Only store meaningful exchanges (skip short greetings/small talk)
      return if user_message.length < 50 && assistant_response.length < 50

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

    RAW_MESSAGES_TO_KEEP = 4

    def build_messages(agent:, memory_context: nil)
      messages = []

      # System prompt — split into cacheable blocks for prompt caching
      core_prompt = agent.full_system_prompt.presence
      system_blocks = []
      system_blocks << { type: "text", text: core_prompt } if core_prompt.present?
      system_blocks << { type: "text", text: memory_context } if memory_context.present?

      # Inject conversation summary for compressed older context
      if @session.conversation_summary.present?
        system_blocks << { type: "text", text: "## Conversation So Far\n#{@session.conversation_summary}" }
      end

      if system_blocks.any?
        messages << { role: "system", content: system_blocks }
      end

      # Only send last few raw messages — older context lives in the summary
      transcript = @session.transcript || []
      transcript.last(RAW_MESSAGES_TO_KEEP).each do |entry|
        messages << { role: entry["role"], content: entry["content"] }
      end

      messages
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

    # ----- Memory Consolidation -----

    def maybe_consolidate
      transcript_size = @session.transcript&.size || 0

      # Consolidate every 20 turns (10 user + 10 assistant messages)
      return unless transcript_size > 0 && (transcript_size % 20).zero?

      MemoryConsolidationJob.perform_later(@session.id)
    rescue StandardError => e
      Rails.logger.warn("[Sessions::Chat] Consolidation trigger failed: #{e.message}")
    end
  end
end
