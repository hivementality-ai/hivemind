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

    # ── Attachments ──────────────────────────────────────────────
    attachment_result = Sessions::AttachmentProcessor.call(attachment_ids: attachment_ids, user_message: effective_message)
    if attachment_result.success?
      image_attachments = attachment_result.data[:images]
      doc_attachments = attachment_result.data[:documents]
      effective_message = attachment_result.data[:effective_message]
    else
      image_attachments = []
      doc_attachments = []
    end

    # Detect sub-agent callbacks and broadcast them to UI
    is_callback = user_message.start_with?("[Sub-agent result")
    if is_callback
      ActionCable.server.broadcast(channel, { type: "sub_agent_callback", content: user_message })
    end

    # Build transcript entry (with image/file refs)
    transcript_entry = { "role" => "user", "content" => effective_message, "timestamp" => Time.current.iso8601 }
    transcript_entry["source"] = "sub_agent" if is_callback
    if image_attachments.any?
      transcript_entry["images"] = image_attachments.map do |a|
        { "attachment_id" => a.id, "content_type" => a.content_type, "filename" => a.filename }
      end
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

    # Broadcast attachment metadata for UI
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

    # ── Build LLM messages ───────────────────────────────────────
    message_result = Sessions::MessageBuilder.call(session:, agent:, current_images: image_attachments, prompt_addons: hashtag_result.prompt_addons)
    messages = message_result.data[:messages]

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

      # Inject MCP tool context for OAuth path
      oauth_mcp = adapter.is_a?(Providers::AnthropicAdapter) && adapter.send(:oauth_token?) && tools.any?
      if oauth_mcp
        llm_options[:agent_id] = agent.id
        llm_options[:session_id] = session.id
        llm_options[:tool_definitions] = tools.map(&:to_llm_tool)
      end

      thinking_content = nil
      show_thinking = agent.thinking_enabled? && agent.thinking_visibility == "debug"

      if tools.any? && !oauth_mcp
        result = Agents::ToolLoop.call(
          adapter:, agent:, session:, messages:, tools:, channel:, options: llm_options
        )
        full_content = result&.data&.dig(:content).to_s
        thinking_content = result&.data&.dig(:thinking)
      else
        full_content = +""
        full_thinking = +""
        result = adapter.chat(messages:, options: llm_options) do |chunk|
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
          when "tool_start"
            ActionCable.server.broadcast(channel, { type: "tool_start", tool: chunk[:tool], input: chunk[:input] })
          when "tool_result"
            ActionCable.server.broadcast(channel, { type: "tool_result", tool: chunk[:tool], output: chunk[:output], success: chunk[:success] })
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

      # ── Post-processing (usage, memory, summarization, origin delivery) ──
      usage = result&.data&.dig(:usage) || {}
      Rails.logger.info("[ChatStreamJob] Usage: in=#{usage[:input_tokens]} out=#{usage[:output_tokens]} cache_create=#{usage[:cache_creation_input_tokens]} cache_read=#{usage[:cache_read_input_tokens]}")
      Sessions::PostProcessor.call(agent:, session:, user_message:, assistant_response: full_content, usage:)

      ActionCable.server.broadcast(channel, { type: "done", content: full_content })

    rescue AgentInterrupted
      if full_content.present?
        session.append_transcript({ "role" => "assistant", "content" => full_content + "\n\n_[Cancelled by user]_", "timestamp" => Time.current.iso8601 })
      end
      ActionCable.server.broadcast(channel, { type: "cancelled", content: full_content })
      Rails.logger.info("ChatStreamJob: cancelled by user for session #{session.id}")

    rescue AgentRedirected => e
      if full_content.present?
        session.append_transcript({ "role" => "assistant", "content" => full_content + "\n\n_[Redirected by user]_", "timestamp" => Time.current.iso8601 })
      end
      ActionCable.server.broadcast(channel, { type: "redirected", content: e.redirect_message })
      Rails.logger.info("ChatStreamJob: redirected for session #{session.id}")
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
      Redis.current.setex(key, 600, "1")
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
    tools = assigned.any? ? assigned : Tool.enabled.builtin.to_a

    tools << SystemTool::LOAD_SKILL if agent.skills.enabled.any?

    tools
  end
end
