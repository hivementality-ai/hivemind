# frozen_string_literal: true

class ChatStreamJob < ApplicationJob
  queue_as :default

  def perform(session_id, user_message, attachment_ids = [])
    session = Session.find(session_id)
    agent = session.agent
    channel = "session_#{session.id}"

    # Mark session as processing so UI can show indicator on reconnect
    set_processing(session.id, true)
    ActionCable.server.broadcast(channel, { type: "processing", active: true })

    # ── Hashtag Actions ──────────────────────────────────────────
    hashtag_result = HashtagActions::Processor.call(
      message: user_message,
      agent: agent,
      session: session
    )

    if hashtag_result.bypass_llm
      # Actions handled everything — broadcast response and return
      # Note: User message already broadcast by controller for instant feedback
      session.append_transcript({ "role" => "user", "content" => user_message, "timestamp" => Time.current.iso8601 })

      response = hashtag_result.response
      if response.present?
        session.append_transcript({ "role" => "assistant", "content" => response, "timestamp" => Time.current.iso8601 })
        ActionCable.server.broadcast(channel, { type: "token", content: response })
      end
      ActionCable.server.broadcast(channel, { type: "done", content: response.to_s })
      return
    end

    # Use cleaned message (hashtags stripped) for LLM
    effective_message = hashtag_result.clean_message.presence || user_message

    # Load attachments (images + documents)
    attachments = attachment_ids.present? ? ChatAttachment.where(id: attachment_ids) : []
    image_attachments = attachments.select(&:image?)
    doc_attachments = attachments.select(&:document?)

    # Save documents to workspace and tell agent the paths
    if doc_attachments.any?
      saved_paths = save_docs_to_workspace(doc_attachments)
      if saved_paths.any?
        file_list = saved_paths.map do |f|
          line = "  - #{f[:path]} (#{f[:filename]}, #{f[:size]})"
          line += " — #{f[:note]}" if f[:note]
          line
        end.join("\n")
        effective_message = "#{effective_message}\n\n[Attached Files — saved to workspace]\n#{file_list}\n\nUse the file_read tool to read these files."
      end
    end

    # Detect sub-agent callbacks and broadcast them to UI
    is_callback = user_message.start_with?("[Sub-agent result")
    if is_callback
      ActionCable.server.broadcast(channel, { type: "sub_agent_callback", content: user_message })
    end

    # Build transcript entry (with image/file refs)
    # Use effective_message so the LLM sees file paths on subsequent turns
    # Sub-agent callbacks use "user" role for LLM compatibility but are marked as callbacks
    transcript_entry = { "role" => "user", "content" => effective_message, "timestamp" => Time.current.iso8601 }
    transcript_entry["source"] = "sub_agent" if is_callback
    if image_attachments.any?
      transcript_entry["images"] = image_attachments.map do |a|
        { "attachment_id" => a.id, "content_type" => a.content_type, "filename" => a.filename }
      end
      # Update attachment message_index
      message_index = (session.transcript || []).size
      image_attachments.each { |a| a.update(message_index: message_index) }
    end
    if doc_attachments.any?
      transcript_entry["files"] = doc_attachments.map do |a|
        { "attachment_id" => a.id, "content_type" => a.content_type, "filename" => a.filename, "byte_size" => a.byte_size }
      end
    end

    session.transcript << transcript_entry
    session.save!

    # Note: User message is already broadcast by SessionsController#message
    # for instant feedback. We only broadcast here if there are attachments
    # that need URLs resolved (which the controller can't do yet).
    if image_attachments.any? || doc_attachments.any?
      broadcast_data = { type: "user_message", content: user_message }
      if doc_attachments.any?
        broadcast_data[:files] = doc_attachments.map do |a|
          { filename: a.filename, content_type: a.content_type, byte_size: a.byte_size }
        end
      end
      if image_attachments.any?
        broadcast_data[:images] = image_attachments.map do |a|
          { id: a.id, filename: a.filename, url: rails_blob_url(a) }
        end
      end
      ActionCable.server.broadcast(channel, broadcast_data)
    end

    # Resolve provider
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent:)
    unless resolver.success?
      ActionCable.server.broadcast(channel, { type: "error", content: resolver.error })
      return
    end

    adapter = resolver.data[:adapter]

    # Build messages for LLM (with vision content + hashtag addons)
    messages = build_messages(session:, agent:, current_images: image_attachments, prompt_addons: hashtag_result.prompt_addons)

    # Prune messages to fit within context budget
    context_manager = Agents::ContextManager.new(agent.llm_model)
    messages = context_manager.prune_messages(messages)

    # If there's a hashtag response to prepend (non-bypass actions), broadcast it
    if hashtag_result.response.present?
      ActionCable.server.broadcast(channel, { type: "token", content: "#{hashtag_result.response}\n\n---\n\n" })
    end

    # Resolve tools
    tools = resolve_tools(agent)

    begin
      # Build LLM options (with thinking if enabled)
      llm_options = { model: agent.llm_model, max_tokens: 8192 }
      if agent.thinking_enabled?
        llm_options[:thinking_enabled] = true
        llm_options[:thinking_budget_tokens] = agent.thinking_budget_tokens || 10_000
      end

      thinking_content = nil
      show_thinking = agent.thinking_enabled? && agent.thinking_visibility == "debug"

      if tools.any?
        result = Agents::ToolLoop.call(
          adapter:,
          agent:,
          session:,
          messages:,
          tools:,
          channel:,
          options: llm_options
        )
        full_content = result&.data&.dig(:content).to_s
        thinking_content = result&.data&.dig(:thinking)
      else
        full_content = +""
        full_thinking = +""
        result = adapter.chat(
          messages:,
          options: llm_options
        ) do |chunk|
          case chunk[:type]
          when "thinking_start"
            ActionCable.server.broadcast(channel, { type: "thinking_start" }) if show_thinking
          when "thinking"
            full_thinking << chunk[:content] if chunk[:content]
            ActionCable.server.broadcast(channel, { type: "thinking", content: chunk[:content] }) if show_thinking
          when "thinking_stop"
            ActionCable.server.broadcast(channel, { type: "thinking_stop" }) if show_thinking
          when "content"
            if chunk[:content]
              full_content << chunk[:content]
              ActionCable.server.broadcast(channel, { type: "token", content: chunk[:content] })
            end
          end
        end

        thinking_content = full_thinking.presence

        if full_content.empty? && result&.success?
          full_content = result.data[:content].to_s
          thinking_content ||= result.data[:thinking]
          ActionCable.server.broadcast(channel, { type: "token", content: full_content })
        elsif full_content.empty? && result && !result.success?
          error_msg = "⚠️ LLM error: #{result.error}"
          ActionCable.server.broadcast(channel, { type: "error", content: error_msg })
          Rails.logger.error("ChatStreamJob LLM failure: #{result.error}")
          full_content = error_msg
        end
      end

      # Append assistant response (thinking stored as metadata, not visible content)
      session.reload
      transcript_entry = { "role" => "assistant", "content" => full_content, "timestamp" => Time.current.iso8601 }
      transcript_entry["thinking"] = thinking_content if thinking_content.present?
      session.transcript << transcript_entry
      session.save!

      # Track usage
      usage = result&.data&.dig(:usage) || {}
      Rails.logger.info("[ChatStreamJob] Usage: in=#{usage[:input_tokens]} out=#{usage[:output_tokens]} cache_create=#{usage[:cache_creation_input_tokens]} cache_read=#{usage[:cache_read_input_tokens]}")
      track_usage(agent:, session:, usage:)

      # Store memory
      store_memory(agent:, session:, user_message:, assistant_response: full_content)

      # Summarize older transcript to keep future requests lean
      maybe_summarize(session)

      # Deliver to origin channel (e.g., WhatsApp) if this session came from one
      Channels::OriginDelivery.call(session: session, content: full_content, agent: agent)

      ActionCable.server.broadcast(channel, { type: "done", content: full_content })

    rescue AgentInterrupted
      # User cancelled — save partial output and notify
      if full_content.present?
        session.append_transcript({ "role" => "assistant", "content" => full_content + "\n\n_[Cancelled by user]_", "timestamp" => Time.current.iso8601 })
      end
      ActionCable.server.broadcast(channel, { type: "cancelled", content: full_content })
      Rails.logger.info("ChatStreamJob: cancelled by user for session #{session.id}")

    rescue AgentRedirected => e
      # User redirected — save partial output, then start new task
      if full_content.present?
        session.append_transcript({ "role" => "assistant", "content" => full_content + "\n\n_[Redirected by user]_", "timestamp" => Time.current.iso8601 })
      end
      ActionCable.server.broadcast(channel, { type: "redirected", content: e.redirect_message })
      Rails.logger.info("ChatStreamJob: redirected for session #{session.id}")

      # Fire new ChatStreamJob with the redirect message
      ChatStreamJob.perform_later(session.id, e.redirect_message, [])

    rescue StandardError => e
      ActionCable.server.broadcast(channel, { type: "error", content: "Error: #{e.message}" })
      Rails.logger.error("ChatStreamJob error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    ensure
      set_processing(session.id, false)
      ActionCable.server.broadcast(channel, { type: "processing", active: false })
    end
  end

  private

  def set_processing(session_id, active)
    key = "session_processing:#{session_id}"
    if active
      Redis.current.setex(key, 600, "1") # 10 min TTL as safety net
    else
      Redis.current.del(key)
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to set processing flag: #{e.message}")
  end

  def rails_blob_url(attachment)
    return nil unless attachment.file.attached?

    Rails.application.routes.url_helpers.rails_blob_path(attachment.file, only_path: true)
  end

  def resolve_tools(agent)
    assigned = agent.agent_tools.includes(:tool).map(&:tool).select(&:enabled?)
    return assigned if assigned.any?

    Tool.enabled.builtin.to_a
  end

  SUMMARIZE_EVERY = 6 # Summarize after every 6 new transcript entries (~3 turns)
  RAW_MESSAGES_TO_KEEP = 4 # Keep last 4 messages raw (2 full turns)

  def build_messages(session:, agent:, current_images: [], prompt_addons: [])
    messages = []

    # System prompt — structured as cacheable blocks
    # Block 1: core identity + role (very stable)
    # Block 2: skills (stable, often the biggest chunk)
    # Block 3: memory + context (semi-stable, changes across sessions)
    system_blocks = agent.respond_to?(:system_prompt_blocks) ? agent.system_prompt_blocks : [{ type: "text", text: agent.full_system_prompt.presence || "You are #{agent.name}, a helpful AI assistant." }]

    # Dynamic context block (memory, mood, addons, summary)
    dynamic_parts = []
    memory_context = recall_memories(agent:, session:)
    dynamic_parts << memory_context if memory_context.present?

    if (mood = session.metadata&.dig("mood"))
      dynamic_parts << "## Style Override\nAdjust your communication style: #{mood}"
    end

    prompt_addons.each { |addon| dynamic_parts << addon }

    if session.conversation_summary.present?
      dynamic_parts << "## Conversation So Far\n#{session.conversation_summary}"
    end

    if dynamic_parts.any?
      system_blocks << { type: "text", text: dynamic_parts.join("\n\n") }
    end

    messages << { role: "system", content: system_blocks }

    # Only send last few raw messages — older context lives in the summary
    transcript = session.transcript
    recent = transcript.last(RAW_MESSAGES_TO_KEEP)
    recent.each_with_index do |msg, idx|
      if msg["role"] == "user" && msg["images"].present? && idx == recent.size - 1
        # Current message with images — build multimodal content
        messages << build_vision_message(msg, current_images)
      elsif msg["role"] == "user" && msg["images"].present?
        # Past message with images — just use text (images aren't re-sent)
        text = msg["content"].to_s
        text += "\n[User attached #{msg["images"].size} image(s)]" if msg["images"].any?
        messages << { role: "user", content: text }
      else
        messages << { role: msg["role"], content: msg["content"] }
      end
    end

    messages
  end

  def build_vision_message(msg, image_attachments)
    content_blocks = []

    # Add images first
    image_attachments.each do |attachment|
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

    # Add text
    text = msg["content"].to_s
    content_blocks << { type: "text", text: text } if text.present?

    { role: "user", content: content_blocks }
  end

  def recall_memories(agent:, session:)
    last_user_msg = session.transcript.select { |m| m["role"] == "user" }.last
    return nil unless last_user_msg

    query = last_user_msg["content"].to_s
    return nil if query.length < 5

    result = Memory::ContextBuilder.call(agent: agent, query: query)
    result[:context]
  rescue StandardError => e
    Rails.logger.warn("Memory recall failed: #{e.message}")
    nil
  end

  def track_usage(agent:, session:, usage:)
    return if usage.blank?

    input_tokens = usage[:input_tokens] || 0
    output_tokens = usage[:output_tokens] || 0
    cost = CostEstimator.estimate(model: agent.llm_model, input_tokens:, output_tokens:)

    UsageRecord.create(
      agent:,
      session:,
      provider: agent.model_provider,
      llm_model: agent.llm_model,
      input_tokens:,
      output_tokens:,
      cost_cents: cost
    )
  end

  # Cost estimation moved to CostEstimator service

  def save_docs_to_workspace(doc_attachments)
    upload_dir = "/workspace/uploads/#{Date.current.iso8601}"
    FileUtils.mkdir_p(upload_dir)

    doc_attachments.filter_map do |doc|
      next unless doc.file.attached?

      safe_name = doc.filename.to_s.gsub(/[^a-zA-Z0-9._-]/, "_")
      timestamped = "#{Time.current.strftime('%H%M%S')}_#{safe_name}"
      path = File.join(upload_dir, timestamped)
      data = doc.file.download

      File.binwrite(path, data)

      size = doc.byte_size < 1024 ? "#{doc.byte_size}B" : doc.byte_size < 1_048_576 ? "#{(doc.byte_size / 1024.0).round(1)}KB" : "#{(doc.byte_size / 1_048_576.0).round(1)}MB"
      result = { path: path, filename: doc.filename.to_s, size: size }

      if doc.content_type == "application/pdf"
        result[:note] = "PDF — use the pdf_read tool (not file_read) to extract text, metadata, or tables"
      elsif !doc.content_type.to_s.start_with?("text/") && !%w[application/json application/xml].include?(doc.content_type)
        result[:note] = "Binary file — may not be directly readable with file_read"
      end

      result
    rescue StandardError => e
      Rails.logger.warn("Failed to save doc to workspace: #{e.message}")
      nil
    end
  end

  # Trigger rolling summarization every N transcript entries.
  # The summary job compresses older messages into ~200 tokens.
  def maybe_summarize(session)
    transcript_size = session.transcript&.size || 0
    summarized_through = session.summary_through_index || 0
    unsummarized = transcript_size - summarized_through

    return if unsummarized < SUMMARIZE_EVERY + RAW_MESSAGES_TO_KEEP

    ConversationSummaryJob.perform_later(session.id)
  rescue StandardError => e
    Rails.logger.warn("[ChatStreamJob] Summary trigger failed: #{e.message}")
  end

  def store_memory(agent:, session:, user_message:, assistant_response:)
    return if user_message.length < 50 && assistant_response.length < 50

    content = "User asked: #{user_message.truncate(200)}\nAssistant: #{assistant_response.truncate(500)}"

    entry = MemoryEntry.create(
      agent:,
      content:,
      source: session,
      memory_type: "episodic",
      metadata: { session_id: session.id, stored_at: Time.current.iso8601 }
    )

    if entry.persisted?
      MemoryEmbeddingJob.perform_later(entry.id)
      MemoryExtractionJob.perform_later(agent.id, user_message, assistant_response)
    end
  rescue StandardError => e
    Rails.logger.warn("Memory store failed: #{e.message}")
  end
end
