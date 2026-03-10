# frozen_string_literal: true

module Sessions
  class PostProcessor
    SUMMARIZE_EVERY = 6
    RAW_MESSAGES_TO_KEEP = 4

    def self.call(...)
      new(...).call
    end

    def initialize(agent:, session:, user_message:, assistant_response:, usage: {})
      @agent = agent
      @session = session
      @user_message = user_message
      @assistant_response = assistant_response
      @usage = usage
    end

    def call
      track_usage
      store_memory
      maybe_summarize
      maybe_generate_title
      deliver_to_origin

      ServiceResponse.success
    rescue StandardError => e
      Rails.logger.error("[Sessions::PostProcessor] Error: #{e.message}")
      ServiceResponse.failure(error: e.message)
    end

    private

    # Each step rescues independently so one failure doesn't block the rest.

    def track_usage
      return if @usage.blank?

      input_tokens = @usage[:input_tokens] || 0
      output_tokens = @usage[:output_tokens] || 0
      cost = CostEstimator.estimate(model: @agent.llm_model, input_tokens:, output_tokens:)

      UsageRecord.create(
        agent: @agent,
        session: @session,
        provider: @agent.model_provider,
        llm_model: @agent.llm_model,
        input_tokens:,
        output_tokens:,
        cost_cents: cost,
        request_payload: @usage[:request_payload]
      )
    rescue StandardError => e
      Rails.logger.warn("[Sessions::PostProcessor] Usage tracking failed: #{e.message}")
    end

    def store_memory
      return if @user_message.length < 50 && @assistant_response.length < 50

      content = "User asked: #{@user_message.truncate(200)}\nAssistant: #{@assistant_response.truncate(500)}"

      entry = MemoryEntry.create(
        agent: @agent,
        content:,
        source: @session,
        memory_type: "episodic",
        metadata: { session_id: @session.id, stored_at: Time.current.iso8601 }
      )

      if entry.persisted?
        MemoryEmbeddingJob.perform_later(entry.id)
        MemoryExtractionJob.perform_later(@agent.id, @user_message, @assistant_response)
      end
    rescue StandardError => e
      Rails.logger.warn("[Sessions::PostProcessor] Memory storage failed: #{e.message}")
    end

    def maybe_summarize
      transcript_size = @session.transcript&.size || 0
      summarized_through = @session.summary_through_index || 0
      unsummarized = transcript_size - summarized_through

      return if unsummarized < SUMMARIZE_EVERY + RAW_MESSAGES_TO_KEEP

      ConversationSummaryJob.perform_later(@session.id)
    rescue StandardError => e
      Rails.logger.warn("[Sessions::PostProcessor] Summary trigger failed: #{e.message}")
    end

    def maybe_generate_title
      existing_title = @session.title.to_s.strip
      return if existing_title.present? && existing_title != "New Chat"

      transcript_size = @session.transcript&.size || 0
      return if transcript_size < 2

      SessionTitleJob.perform_later(@session.id)
    rescue StandardError => e
      Rails.logger.warn("[Sessions::PostProcessor] Title generation trigger failed: #{e.message}")
    end

    def deliver_to_origin
      Channels::OriginDelivery.call(session: @session, content: @assistant_response, agent: @agent)
    rescue StandardError => e
      Rails.logger.warn("[Sessions::PostProcessor] Origin delivery failed: #{e.message}")
    end
  end
end
