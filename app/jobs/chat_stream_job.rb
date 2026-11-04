# frozen_string_literal: true

class ChatStreamJob < ApplicationJob
  include TaskPipelineContinuation

  queue_as :agents

  PROCESSING_KEY_PREFIX = "session_processing:"
  LOCK_KEY_PREFIX = "session_turn_lock:"
  FALLBACK_NOTICE = "_Claude was unavailable, so the backup brain answered._"
  # The lock is short-lived and renewed by a heartbeat while a turn runs, so a
  # dead worker's lock disappears within LOCK_TTL.
  LOCK_TTL = 90
  HEARTBEAT_INTERVAL = 30
  # Backstop only; the flag is cleared at turn end or by StuckTurnSweepJob.
  PROCESSING_TTL = 1.hour.to_i
  # Minimum wall-clock gap between stop/redirect signal reads while streaming.
  SIGNAL_CHECK_INTERVAL = 0.25
  LOCK_RETRY_DELAY = 5.seconds

  RELEASE_LOCK_SCRIPT = "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) end return 0"
  RENEW_LOCK_SCRIPT = <<~LUA.squish
    if redis.call('get', KEYS[1]) == ARGV[1] then
      redis.call('expire', KEYS[2], ARGV[3])
      return redis.call('expire', KEYS[1], ARGV[2])
    end
    return 0
  LUA

  # Runs one turn at a time per session. A turn that arrives while another is
  # running is requeued behind it, on the same queue, rather than dropped.
  def perform(session_id, user_message, attachment_ids = [])
    token = SecureRandom.hex(8)
    lock_key = "#{LOCK_KEY_PREFIX}#{session_id}"
    unless Redis.current.set(lock_key, token, nx: true, ex: LOCK_TTL)
      self.class.set(queue: queue_name, wait: LOCK_RETRY_DELAY).perform_later(session_id, user_message, attachment_ids)
      return
    end

    stop = Thread::Queue.new
    heartbeat = start_heartbeat(lock_key, "#{PROCESSING_KEY_PREFIX}#{session_id}", token, stop)
    begin
      run_turn(session_id, user_message, attachment_ids)
    ensure
      stop << true
      heartbeat.join
      set_processing(session_id, false)
      Redis.current.eval(RELEASE_LOCK_SCRIPT, keys: [ lock_key ], argv: [ token ])
    end
  end

  def run_turn(session_id, user_message, attachment_ids)
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
    brain = Sessions::BrainResolver.call(session:, agent:)
    resolver = Providers::Resolver.call(provider_name: brain.provider_name, agent:, provider_config: brain.provider_config)
    unless resolver.success?
      ActionCable.server.broadcast(channel, { type: "error", content: resolver.error })
      return
    end

    adapter = resolver.data[:adapter]

    # ── Budget enforcement ───────────────────────────────────────
    budget_check = Budgets::Check.call(agent: agent)
    unless budget_check.success?
      msg = "Agent #{agent.name} has exceeded its budget for this period."
      ActionCable.server.broadcast(channel, { type: "error", content: msg })
      return
    end

    # ── Build LLM messages ───────────────────────────────────────
    message_result = Sessions::MessageBuilder.call(session:, agent:, current_images: image_attachments, prompt_addons: hashtag_result.prompt_addons)
    messages = message_result.data[:messages]

    # Prune messages to fit within context budget
    context_manager = Agents::ContextManager.new(brain.model, 8192, provider: brain.provider_name, agent: agent)
    messages = context_manager.prune_messages(messages)

    # If there's a hashtag response to prepend (non-bypass actions), broadcast it
    if hashtag_result.response.present?
      ActionCable.server.broadcast(channel, { type: "token", content: "#{hashtag_result.response}\n\n---\n\n" })
    end

    # Resolve tools
    tools = resolve_tools(agent)

    begin
      # Build LLM options (with thinking if enabled)
      resolved_model = resolve_model(brain, agent, effective_message)
      llm_options = { model: resolved_model, max_tokens: agent.max_output_tokens || 8192 }
      llm_options.merge!(agent.inference_options)
      if agent.thinking_enabled?
        llm_options[:thinking_enabled] = true
        llm_options[:thinking_budget_tokens] = agent.thinking_budget_tokens || 10_000
      end

      # SDK-proxy path — default for OAuth (sk-ant-oat) tokens so chats run
      # through Claude Code and bill against the subscription's included usage.
      # Can be forced off via the "anthropic_use_sdk_proxy" Setting (or the
      # USE_SDK_PROXY_FALLBACK env). Non-OAuth keys drive Agents::ToolLoop.
      base_adapter = Providers::FailoverAdapter.unwrap(adapter)
      oauth_mcp = Providers::AnthropicAdapter.sdk_proxy_enabled? &&
                  base_adapter.is_a?(Providers::AnthropicAdapter) &&
                  base_adapter.send(:oauth_token?) &&
                  tools.any?
      if oauth_mcp
        llm_options[:agent_id] = agent.id
        llm_options[:session_id] = session.id
        llm_options[:tool_definitions] = tools.map(&:to_llm_tool)
      end

      thinking_content = nil
      show_thinking = agent.thinking_enabled? && agent.thinking_visibility == "debug"

      Plugins::Hooks.trigger("before_chat", agent: agent, session: session, messages: messages)

      if tools.any? && !oauth_mcp
        result = Agents::ToolLoop.call(
          adapter:, agent:, session:, messages:, tools:, channel:, options: llm_options
        ) { |_delta| check_stream_signal!(session) }
        if result && !result.success?
          error_msg = "⚠️ LLM error: #{result.error}"
          ActionCable.server.broadcast(channel, { type: "error", content: error_msg })
          Rails.logger.error("ChatStreamJob ToolLoop failure: #{result.error}")
          full_content = error_msg
        else
          full_content = result&.data&.dig(:content).to_s
          thinking_content = result&.data&.dig(:thinking)
          tool_history = result&.data&.dig(:tool_history)
        end
      else
        full_content = +""
        full_thinking = +""
        tool_activity = false
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
              check_stream_signal!(session)
            end
          when "tool_start"
            tool_activity = true
            Plugins::Hooks.trigger("before_tool_call", tool_name: chunk[:tool], input: chunk[:input] || {}, agent: agent, source: :proxy)
            ActionCable.server.broadcast(channel, { type: "tool_start", tool: chunk[:tool], input: chunk[:input] })
          when "tool_result"
            Plugins::Hooks.trigger("after_tool_call", tool_name: chunk[:tool], output: chunk[:output], success: chunk[:success], agent: agent, source: :proxy)
            ActionCable.server.broadcast(channel, { type: "tool_result", tool: chunk[:tool], output: chunk[:output], success: chunk[:success] })
          end
        end

        thinking_content = full_thinking.presence

        fallback_brain = oauth_mcp && full_content.empty? && !tool_activity &&
                         Providers::FailoverAdapter.failover_worthy?(result) &&
                         Providers::DefaultFallback.call(failed: brain.provider_config, failed_adapter_type: brain.provider_name)
        if fallback_brain
          result = run_fallback_tool_loop(fallback_brain, agent:, session:, messages:, tools:, channel:, llm_options:, primary_error: result.error)
          if result.success?
            full_content = "#{FALLBACK_NOTICE}\n\n#{result.data[:content]}"
            thinking_content = result.data[:thinking]
            tool_history = result.data[:tool_history]
          else
            full_content = "⚠️ LLM error: #{result.error}"
            ActionCable.server.broadcast(channel, { type: "error", content: full_content })
          end
        elsif full_content.empty? && result&.success?
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

      Plugins::Hooks.trigger("after_chat", agent: agent, session: session, content: full_content)

      # Append assistant response (thinking stored as metadata, not visible content)
      session.reload
      transcript_entry = { "role" => "assistant", "content" => full_content, "timestamp" => Time.current.iso8601 }
      transcript_entry["thinking"] = thinking_content if thinking_content.present?
      transcript_entry["tool_calls"] = tool_history if tool_history.present?
      session.transcript << transcript_entry
      session.save!

      # ── Post-processing (usage, memory, summarization, origin delivery) ──
      usage = result&.data&.dig(:usage) || {}
      Rails.logger.info("[ChatStreamJob] Usage: in=#{usage[:input_tokens]} out=#{usage[:output_tokens]} cache_create=#{usage[:cache_creation_input_tokens]} cache_read=#{usage[:cache_read_input_tokens]}")
      Sessions::PostProcessor.call(agent:, session:, user_message:, assistant_response: full_content, usage:)

      ActionCable.server.broadcast(channel, { type: "done", content: full_content })

      # Push notification for mobile users
      WebPush::NotificationTriggers.agent_response(session: session, content: full_content)

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
      ChatStreamJob.set(queue: :interactive).perform_later(session.id, e.redirect_message, [])

    rescue StandardError => e
      ActionCable.server.broadcast(channel, { type: "error", content: "Error: #{e.message}" })
      Rails.logger.error("ChatStreamJob error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      WebPush::NotificationTriggers.session_error(session: session, message: e.message)
    ensure
      set_processing(session.id, false)
      ActionCable.server.broadcast(channel, { type: "processing", active: false })

      # Close hook sessions so they don't accumulate as zombies
      if session.metadata&.dig("type")&.start_with?("task_hook")
        session.update_columns(status: "completed", last_activity_at: Time.current)
        WebhookEmitter.emit(
          "session.completed",
          { session_id: session.id, agent_id: session.agent_id, title: session.title, completed_at: Time.current.iso8601 },
          agent: agent
        )
      end

      # Finalize heartbeat sessions — create HeartbeatRun record and restore
      # the system assistant's model/provider. This runs here because the
      # HeartbeatJob now dispatches async via ChatStreamJob instead of calling
      # Sessions::Chat synchronously (freeing the system-queue thread).
      finalize_heartbeat_session(session, full_content, tool_history) if session.metadata&.dig("type") == "heartbeat"

      # Continue task hook pipeline if this session is part of one
      continue_task_pipeline_if_needed(session)
    end
  end

  private

  private :run_turn

  # Renews the turn lock (and the processing flag) while the turn runs; stops
  # once the lock is no longer ours.
  # Renews the lock every HEARTBEAT_INTERVAL until +stop+ receives a value.
  # Stopping through the queue, not Thread#kill, never interrupts a Redis call.
  def start_heartbeat(lock_key, flag_key, token, stop)
    Thread.new do
      loop do
        break if stop.pop(timeout: HEARTBEAT_INTERVAL)
        renewed = Redis.current.eval(RENEW_LOCK_SCRIPT, keys: [ lock_key, flag_key ], argv: [ token, LOCK_TTL, PROCESSING_TTL ])
        break if renewed.to_i.zero?
      end
    rescue StandardError => e
      Rails.logger.warn("[ChatStreamJob] Lock heartbeat stopped: #{e.message}")
    end
  end

  # Reads the stop/redirect signal at most once per SIGNAL_CHECK_INTERVAL so a
  # long stream does not hit Redis for every token.
  def check_stream_signal!(session)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @signal_checked_at && now - @signal_checked_at < SIGNAL_CHECK_INTERVAL
    @signal_checked_at = now

    signal = SessionSignal.check(session.id)
    return unless signal

    case signal[:type]
    when "cancel"
      raise AgentInterrupted
    when "redirect"
      raise AgentRedirected.new(signal[:message])
    end
  end

  def set_processing(session_id, active)
    key = "#{PROCESSING_KEY_PREFIX}#{session_id}"
    if active
      Redis.current.setex(key, PROCESSING_TTL, "1")
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

  # Called from the ensure block when a heartbeat session completes.
  # Creates the HeartbeatRun record, restores the system assistant's
  # original model/provider, and handles memory overwrite — all the
  # work that HeartbeatJob used to do synchronously.
  def finalize_heartbeat_session(session, reply, tool_history)
    meta = session.metadata || {}
    agent = session.agent
    reply = reply.to_s.strip

    started_at = meta["started_at"] ? Time.parse(meta["started_at"]) : session.created_at
    duration_ms = ((Time.current - started_at) * 1000).to_i
    is_ok = reply.blank? || reply.match?(/\AHEARTBEAT_OK\z/i)
    tool_count = tool_history&.size || 0

    if tool_count == 0
      Rails.logger.warn("[Heartbeat] Model returned response with ZERO tool calls — likely fabricated results")
    end

    session.update_columns(status: "completed", last_activity_at: Time.current)
    WebhookEmitter.emit(
      "session.completed",
      { session_id: session.id, agent_id: session.agent_id, title: session.title, completed_at: Time.current.iso8601 },
      agent: agent
    )

    HeartbeatRun.create!(
      agent: agent,
      session: session,
      status: reply.present? ? (is_ok ? "ok" : "action_taken") : "error",
      summary: reply.presence&.truncate(2000),
      previous_summary: meta["previous_summary"]&.truncate(2000),
      input_tokens: 0,
      output_tokens: 0,
      duration_ms: duration_ms,
      model: meta["heartbeat_model"] || agent.llm_model,
      metadata: { tasks_count: meta["tasks_count"] || 0, tool_calls_count: tool_count, tool_history: tool_history&.first(20) }
    )

    # Restore original model and provider on the system assistant
    original_model = meta["original_model"]
    original_provider = meta["original_provider"]
    if original_model.present? && original_model != agent.llm_model
      agent.update_column(:llm_model, original_model)
      agent.update_column(:model_provider, original_provider) if original_provider.present?
    end

    # Overwrite the system assistant's single memory with the latest summary
    if reply.present?
      ActiveRecord::Base.transaction do
        agent.memory_entries.destroy_all
        MemoryEntry.create!(
          agent: agent,
          content: reply.truncate(2000),
          memory_type: "semantic",
          importance: 1.0,
          metadata: { source: "heartbeat", updated_at: Time.current.iso8601 }
        )
      end
    end

    # Broadcast if action was taken
    unless is_ok
      ActionCable.server.broadcast(
        "session_#{session.session_key}",
        { type: "heartbeat", content: reply, timestamp: Time.current.iso8601 }
      )
    end
  rescue StandardError => e
    Rails.logger.error("[Heartbeat] Finalization failed: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}")
  end

  # Re-runs the turn on the default backup brain through Agents::ToolLoop with
  # the same tools the sdk-proxy path was given, after telling the user.
  def run_fallback_tool_loop(brain, agent:, session:, messages:, tools:, channel:, llm_options:, primary_error:)
    Rails.logger.warn("[ChatStreamJob] sdk-proxy failed (#{primary_error.to_s.truncate(200)}); falling back to #{brain.provider_name}/#{brain.model}")
    resolved = Providers::Resolver.call(provider_name: brain.provider_name, agent:, provider_config: brain.provider_config, failover: false)
    return resolved unless resolved.success?

    ActionCable.server.broadcast(channel, { type: "token", content: "#{FALLBACK_NOTICE}\n\n" })
    options = llm_options.except(:agent_id, :session_id, :tool_definitions).merge(model: brain.model)
    Agents::ToolLoop.call(
      adapter: resolved.data[:adapter], agent:, session:, messages:, tools:, channel:, options:
    ) { |_delta| check_stream_signal!(session) }
  end

  def resolve_tools(agent)
    assigned = agent.agent_tools.includes(:tool).map(&:tool).select(&:enabled?)
    tools = assigned.any? ? assigned : Tool.enabled.builtin.to_a

    tools << SystemTool::LOAD_SKILL if agent.skills.enabled.any?
    tools.concat(Mcp::ToolResolver.proxies(agent))
    tools.concat(Connectors::ToolResolver.proxies(agent))

    tools
  end

  # Resolves the chat brain's model. If it is "auto" and its provider supports
  # routing (anthropic or openai), delegate to Agents::ModelRouter and log the
  # picked model. Otherwise use the chosen model verbatim.
  def resolve_model(brain, agent, user_message)
    return brain.model unless brain.model.to_s == "auto"
    return brain.model unless Agents::ModelRouter.auto_supported?(brain.provider_name)

    picked = Agents::ModelRouter.route(
      provider: brain.provider_name,
      message_text: user_message.to_s,
      recent_tools: recent_tool_names(agent)
    )
    Rails.logger.info("[ModelRouter] agent=#{agent.id} provider=#{brain.provider_name} picked=#{picked}")
    picked || Agents::ModelRouter::DEFAULT_RULES.dig(brain.provider_name, "tiers", "mid")
  end

  # Peek at the last few tool executions on this agent so ModelRouter can
  # factor tool-trajectory into its routing. Bounded to avoid a big query.
  def recent_tool_names(agent)
    agent.tool_executions
         .joins(:tool)
         .order(created_at: :desc)
         .limit(5)
         .pluck("tools.name")
         .reverse
  rescue StandardError
    []
  end
end
