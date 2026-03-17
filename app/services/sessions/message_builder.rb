# frozen_string_literal: true

module Sessions
  class MessageBuilder
    RAW_MESSAGES_TO_KEEP = 20

    def self.call(...)
      new(...).call
    end

    def initialize(session:, agent:, current_images: [], prompt_addons: [])
      @session = session
      @agent = agent
      @current_images = current_images
      @prompt_addons = prompt_addons
    end

    def call
      messages = []

      messages << build_system_message
      messages.concat(build_transcript_messages)

      ServiceResponse.success(data: { messages: messages })
    rescue StandardError => e
      Rails.logger.error("[Sessions::MessageBuilder] Error: #{e.message}")
      ServiceResponse.failure(error: e.message)
    end

    private

    def build_system_message
      system_blocks = if @agent.respond_to?(:system_prompt_blocks)
                        @agent.system_prompt_blocks
      else
                        [ { type: "text", text: @agent.full_system_prompt.presence || "You are #{@agent.name}, a helpful AI assistant." } ]
      end

      dynamic_parts = []

      memory_context = recall_memories
      dynamic_parts << memory_context if memory_context.present?

      if (mood = @session.metadata&.dig("mood"))
        dynamic_parts << "## Style Override\nAdjust your communication style: #{mood}"
      end

      @prompt_addons.each { |addon| dynamic_parts << addon }

      if @session.conversation_summary.present?
        dynamic_parts << "## Conversation So Far\n#{@session.conversation_summary}"
      end

      if dynamic_parts.any?
        system_blocks << { type: "text", text: dynamic_parts.join("\n\n") }
      end

      { role: "system", content: system_blocks }
    end

    def build_transcript_messages
      transcript = @session.transcript || []
      recent = transcript.last(RAW_MESSAGES_TO_KEEP)

      recent.each_with_index.map do |msg, idx|
        if msg["role"] == "user" && msg["images"].present? && idx == recent.size - 1
          build_vision_message(msg)
        elsif msg["role"] == "user" && msg["images"].present?
          text = msg["content"].to_s
          text += "\n[User attached #{msg["images"].size} image(s)]" if msg["images"].any?
          { role: "user", content: text }
        else
          { role: msg["role"], content: msg["content"] }
        end
      end
    end

    def build_vision_message(msg)
      content_blocks = []

      @current_images.each do |attachment|
        next unless attachment.image? && attachment.file.attached?

        base64 = attachment.to_base64
        next unless base64

        content_blocks << {
          type: "image",
          source: {
            type: "base64",
            media_type: attachment.media_type,
            data: base64
          }
        }
      end

      text = msg["content"].to_s
      content_blocks << { type: "text", text: text } if text.present?

      { role: "user", content: content_blocks }
    end

    def recall_memories
      transcript = @session.transcript || []
      user_messages = transcript.select { |m| m["role"] == "user" }
      last_user_msg = user_messages.last
      return nil unless last_user_msg

      query = last_user_msg["content"].to_s
      return nil if query.length < 5

      # Hybrid context loading:
      # - First 3 user turns: full memory search (session start, establishing context)
      # - After that: only inject preferences (agent has memory_search tool for on-demand recall)
      if user_messages.size <= 3
        result = Memory::ContextBuilder.call(agent: @agent, query: query)
        result[:context]
      else
        # Only preferences after initial turns — they're cheap (no embedding search)
        prefs = MemoryEntry.where(agent: @agent).preferences.by_importance.limit(15)
        return nil unless prefs.any?

        lines = prefs.map { |p| "- #{p.content}" }
        "## Your Memories\nUse these naturally in conversation. Don't mention that you're recalling memories.\n\n### User Preferences\n#{lines.join("\n")}"
      end
    rescue StandardError => e
      Rails.logger.warn("Memory recall failed: #{e.message}")
      nil
    end
  end
end
