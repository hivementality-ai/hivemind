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

      # Inject contextual skills before memory — they shape how the agent thinks
      # about the current task, which in turn affects memory retrieval quality.
      contextual_skills_block = load_contextual_skills
      dynamic_parts << contextual_skills_block if contextual_skills_block.present?

      memory_context = recall_memories
      dynamic_parts << memory_context if memory_context.present?

      task_context = assigned_task_context
      dynamic_parts << task_context if task_context.present?

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

    # Auto-loads contextual skills relevant to the current user message.
    # Runs Skills::AutoLoader against the last user message and injects matching
    # skill content directly into the dynamic prompt block.
    def load_contextual_skills
      return nil unless @agent.respond_to?(:skills) && @agent.skills.enabled.contextual_tier.any?

      transcript = @session.transcript || []
      last_user_msg = transcript.select { |m| m["role"] == "user" }.last
      return nil unless last_user_msg

      context_text = last_user_msg["content"].to_s
      return nil if context_text.length < 5

      result = Skills::AutoLoader.call(
        agent: @agent,
        session: @session,
        context: context_text,
        contextual_only: true
      )

      return nil if result[:contextual_skills].empty?

      lines = [ "## Contextual Skills (auto-loaded for this task)" ]
      result[:contextual_skills].each do |skill|
        lines << "### #{skill.name}"
        lines << skill.content
        lines << ""
      end

      lines.join("\n")
    rescue StandardError => e
      Rails.logger.warn("[MessageBuilder] Contextual skill loading failed: #{e.message}")
      nil
    end

    # Injects the agent's open assigned tasks so they're aware of their workload on wake.
    # Capped at 10 tasks to keep the context tight.
    def assigned_task_context
      return nil unless @agent.is_a?(Agent) && @agent.persisted?

      tasks = Task.for_agent(@agent).open.by_priority.includes(:project, :project_milestone).limit(10)
      return nil if tasks.empty?

      lines = tasks.map(&:to_summary)
      overdue_count = tasks.count(&:overdue?)

      header = "## Your Assigned Tasks (#{tasks.size} open#{overdue_count > 0 ? ", #{overdue_count} overdue" : ""})"
      "#{header}\n#{lines.map { |l| "- #{l}" }.join("\n")}"
    rescue StandardError => e
      Rails.logger.warn("[MessageBuilder] Task context failed: #{e.message}")
      nil
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
