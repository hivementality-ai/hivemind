# frozen_string_literal: true

class TeamChatJob < ApplicationJob
  queue_as :default

  # Process a message in a team chat — route to targeted agent(s), handle responses,
  # and trigger any @mentions in agent responses (chain reactions).
  MAX_CHAIN_DEPTH = 2          # Max @mention chain reactions per user message
  AGENT_COOLDOWN_SECONDS = 10  # Min seconds between an agent's responses

  def perform(team_chat_session_id, message_id, responding_agent_id: nil, chain_depth: 0)
    @session = TeamChatSession.find(team_chat_session_id)
    @team = @session.team
    @channel = "team_chat_#{@session.id}"
    @chain_depth = chain_depth
    message = TeamChatMessage.find(message_id)
    @trigger_message_images = message.images.attached? ? message.images.to_a : []
    @trigger_message_docs = message.documents.attached? ? message.documents.to_a : []

    # Determine which agents should respond
    agents_to_respond = if responding_agent_id
                          # This is a chain reaction — specific agent was @mentioned by another agent
                          [ Agent.find(responding_agent_id) ]
    elsif message.target_agent_id
                          # User @mentioned a specific agent
                          [ message.target_agent ]
    else
                          # No @mention or @team — all enabled team agents respond
                          @team.agents.enabled.order(:name).to_a
    end

    # Apply cooldown — skip agents who responded very recently
    agents_to_respond = agents_to_respond.reject do |agent|
      last_msg = @session.team_chat_messages.where(sender_type: "agent", sender_id: agent.id).order(:created_at).last
      last_msg && last_msg.created_at > AGENT_COOLDOWN_SECONDS.seconds.ago
    end

    @current_round_trigger_id = message.id
    @current_round_agent_ids_responded = []

    agents_to_respond.each do |agent|
      respond_as_agent(agent:, trigger_message: message)
      @current_round_agent_ids_responded << agent.id
    end
  end

  private

  def respond_as_agent(agent:, trigger_message:)
    # Get or create persistent session for this agent in this team chat
    @agent_session = @session.session_for(agent)

    # Persist the triggering message to the agent's session (with file paths if docs attached)
    sender = trigger_message.from_user? ? "user" : (Agent.find_by(id: trigger_message.sender_id)&.name || "agent")
    trigger_content = trigger_message.content.to_s

    # ── Hashtag Actions (before provider resolution — bypass_llm actions don't need a provider) ──
    user = trigger_message.from_user? ? User.find_by(id: trigger_message.sender_id) : nil
    hashtag_result = HashtagActions::Processor.call(
      message: trigger_content,
      agent: agent,
      session: @agent_session,
      user: user
    )

    if hashtag_result.bypass_llm
      # Actions handled everything — broadcast response and return
      @agent_session.append_transcript({ "role" => "user", "content" => "[#{sender}]: #{trigger_content}" })

      response = hashtag_result.response
      @agent_session.append_transcript({ "role" => "assistant", "content" => response })

      # Broadcast response to team chat
      ActionCable.server.broadcast(@channel, {
        type: "token",
        agent_id: agent.id,
        agent_name: agent.name,
        content: response
      })

      ActionCable.server.broadcast(@channel, {
        type: "agent_done",
        agent_id: agent.id,
        agent_name: agent.name,
        content: response
      })

      # Save message to team chat
      @session.team_chat_messages.create!(
        sender_type: "agent",
        sender_id: agent.id,
        content: response,
        metadata: { hashtag_action: true }
      )

      return
    end

    # Use cleaned message (hashtags stripped) for LLM
    trigger_content = hashtag_result.clean_message.presence || trigger_content

    # Broadcast thinking indicator
    ActionCable.server.broadcast(@channel, {
      type: "thinking",
      agent_id: agent.id,
      agent_name: agent.name
    })

    # Resolve provider
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent:)
    unless resolver.success?
      broadcast_error(agent:, error: resolver.error)
      return
    end

    adapter = resolver.data[:adapter]

    # Save docs to workspace (only once, shared across all agents)
    @saved_doc_paths ||= if @trigger_message_docs.any?
                           Rails.logger.info("[TeamChatJob] Saving #{@trigger_message_docs.size} docs to workspace")
                           result = save_docs_to_workspace(@trigger_message_docs)
                           Rails.logger.info("[TeamChatJob] Saved docs: #{result.inspect}")
                           result
    else
                           []
    end

    if @saved_doc_paths.any?
      file_list = @saved_doc_paths.map do |f|
        line = "  - #{f[:path]} (#{f[:filename]}, #{f[:size]})"
        line += " — #{f[:note]}" if f[:note]
        line
      end.join("\n")
      trigger_content = "#{trigger_content}\n\n[Attached Files — saved to workspace]\n#{file_list}\n\nUse the appropriate tool to read these files (file_read for text, pdf_read for PDFs)."
    end

    @agent_session.append_transcript({ "role" => "user", "content" => "[#{sender}]: #{trigger_content}" })

    # Build messages with team context + agent's persistent history + hashtag addons
    messages = build_team_messages(
      agent:,
      images: @trigger_message_images,
      trigger_message_id: trigger_message.id,
      prompt_addons: hashtag_result.prompt_addons
    )

    # Prune messages to fit within context budget
    context_manager = Agents::ContextManager.new(agent.llm_model)
    messages = context_manager.prune_messages(messages)

    tools = resolve_tools(agent)

    begin
      full_content = +""
      thinking_content = nil

      # Build LLM options (with thinking if enabled)
      llm_options = { model: agent.llm_model, max_tokens: 8192 }
      if agent.thinking_enabled?
        llm_options[:thinking_enabled] = true
        llm_options[:thinking_budget_tokens] = agent.thinking_budget_tokens || 10_000
      end

      show_thinking = agent.thinking_enabled? && agent.thinking_visibility == "debug"

      # If there's a hashtag response to prepend (non-bypass actions), broadcast it
      if hashtag_result.response.present?
        ActionCable.server.broadcast(@channel, {
          type: "token",
          agent_id: agent.id,
          agent_name: agent.name,
          content: "#{hashtag_result.response}\n\n---\n\n"
        })
      end

      if tools.any?
        result = Agents::ToolLoop.call(
          adapter:,
          agent:,
          session: @agent_session,
          messages:,
          tools:,
          channel: @channel,
          options: llm_options,
          broadcast_extras: { agent_id: agent.id, agent_name: agent.name }
        )
        full_content = result&.data&.dig(:content).to_s
        thinking_content = result&.data&.dig(:thinking)
      else
        full_thinking = +""
        result = adapter.chat(
          messages:,
          options: llm_options
        ) do |chunk|
          case chunk[:type]
          when "thinking_start"
            ActionCable.server.broadcast(@channel, { type: "thinking_start", agent_id: agent.id, agent_name: agent.name }) if show_thinking
          when "thinking"
            full_thinking << chunk[:content] if chunk[:content]
            ActionCable.server.broadcast(@channel, { type: "thinking_stream", agent_id: agent.id, agent_name: agent.name, content: chunk[:content] }) if show_thinking
          when "thinking_stop"
            ActionCable.server.broadcast(@channel, { type: "thinking_stop", agent_id: agent.id, agent_name: agent.name }) if show_thinking
          when "content"
            if chunk[:content]
              full_content << chunk[:content]
              ActionCable.server.broadcast(@channel, {
                type: "token",
                agent_id: agent.id,
                agent_name: agent.name,
                content: chunk[:content]
              })
            end
          end
        end

        thinking_content = full_thinking.presence

        if full_content.empty? && result&.success?
          full_content = result.data[:content].to_s
          thinking_content ||= result.data[:thinking]
          ActionCable.server.broadcast(@channel, {
            type: "token",
            agent_id: agent.id,
            agent_name: agent.name,
            content: full_content
          })
        end
      end

      # Save the agent's response to team chat (thinking stored in metadata, not content)
      msg_metadata = { model: agent.llm_model, provider: agent.model_provider }
      msg_metadata[:thinking] = thinking_content if thinking_content.present?

      # Strip self-name prefix — LLMs sometimes echo "[Name]: " or "[Name]:" at the start
      full_content = strip_self_name_prefix(full_content, agent)

      Rails.logger.info("TeamChatJob: saving response for #{agent.name}, content length=#{full_content.length}, blank?=#{full_content.blank?}, result_success=#{result&.success?}")
      if full_content.blank?
        Rails.logger.warn("TeamChatJob: empty response from #{agent.name}, result: #{result&.success?}, error: #{result&.error}")
        full_content = "_(No response generated)_"
      end

      agent_message = @session.team_chat_messages.create!(
        sender_type: "agent",
        sender_id: agent.id,
        content: full_content,
        metadata: msg_metadata
      )

      # Persist to agent's individual session transcript (thinking stored as metadata)
      transcript_entry = { "role" => "assistant", "content" => full_content }
      transcript_entry["thinking"] = thinking_content if thinking_content.present?
      @agent_session.append_transcript(transcript_entry)

      # Track usage
      usage = result&.data&.dig(:usage) || {}
      track_usage(agent:, session: @agent_session, usage:)

      ActionCable.server.broadcast(@channel, {
        type: "agent_done",
        agent_id: agent.id,
        agent_name: agent.name,
        content: full_content,
        message_id: agent_message.id
      })

      # Check if the agent @mentioned another agent — trigger chain reaction (with depth limit)
      if @chain_depth < MAX_CHAIN_DEPTH
        mentions = TeamChatMessage.extract_mentions(full_content, @team)
        mentions[:agents].reject { |a| a.id == agent.id }.each do |mentioned_agent|
          TeamChatJob.perform_later(@session.id, agent_message.id, responding_agent_id: mentioned_agent.id, chain_depth: @chain_depth + 1)
        end
      else
        Rails.logger.info("TeamChatJob: chain depth #{@chain_depth} reached max #{MAX_CHAIN_DEPTH}, skipping @mention chains for #{agent.name}")
      end

    rescue StandardError => e
      broadcast_error(agent:, error: e.message)
      Rails.logger.error("TeamChatJob error (#{agent.name}): #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end
  end

  def build_team_messages(agent:, images: [], trigger_message_id: nil, prompt_addons: [])
    messages = []

    # System prompt: agent soul + team soul + hashtag addons
    system_parts = []
    system_parts << agent.full_system_prompt if agent.full_system_prompt.present?
    system_parts << build_team_context(agent:)

    # Inject hashtag action prompt addons
    prompt_addons.each do |addon|
      system_parts << addon
    end

    messages << { role: "system", content: system_parts.join("\n\n") }

    # Chat history — include recent team chat messages for context
    recent = @session.recent_messages(limit: 30)
    # Always include at least the last 5 messages so the agent has context
    recent = @session.team_chat_messages.chronological.last(5) if recent.size < 5
    recent.each_with_index do |msg, idx|
      is_trigger = (msg.id == trigger_message_id)

      if msg.from_user?
        user = User.find_by(id: msg.sender_id)
        name = user&.email&.split("@")&.first || "User"

        # Build message text (with file paths if this is the trigger message with docs)
        msg_text = "[#{name}]: #{msg.content}"
        if is_trigger && @saved_doc_paths&.any?
          file_list = @saved_doc_paths.map do |f|
            line = "  - #{f[:path]} (#{f[:filename]}, #{f[:size]})"
            line += " — #{f[:note]}" if f[:note]
            line
          end.join("\n")
          msg_text += "\n\n[Attached Files — saved to workspace]\n#{file_list}\n\nUse the appropriate tool to read these files (file_read for text, pdf_read for PDFs)."
        elsif msg.documents.attached?
          msg_text += " [attached #{msg.documents.count} file(s)]"
        end

        # Attach images to the trigger message
        if is_trigger && images.any?
          content_blocks = build_image_blocks(images)
          content_blocks << { type: "text", text: msg_text }
          messages << { role: "user", content: content_blocks }
        else
          msg_text += " [attached #{msg.images.count} image(s)]" if msg.images.attached? && !(is_trigger && images.any?)
          messages << { role: "user", content: msg_text }
        end
      elsif msg.from_agent?
        sender_agent = Agent.find_by(id: msg.sender_id)
        if sender_agent && sender_agent.id == agent.id
          messages << { role: "assistant", content: msg.content }
        else
          sender_name = sender_agent&.name || "Agent"
          # Tag messages from agents who responded in this same round as background chatter
          same_round = @current_round_agent_ids_responded&.include?(sender_agent&.id)
          prefix = same_round ? "[While you were thinking, #{sender_name} said]" : "[#{sender_name}]"
          messages << { role: "user", content: "#{prefix}: #{msg.content}" }
        end
      end
    end

    messages
  end

  def save_docs_to_workspace(docs)
    upload_dir = "/workspace/uploads/#{Date.current.iso8601}"
    FileUtils.mkdir_p(upload_dir)

    docs.filter_map do |doc|
      safe_name = doc.filename.to_s.gsub(/[^a-zA-Z0-9._-]/, "_")
      timestamped = "#{Time.current.strftime('%H%M%S')}_#{safe_name}"
      path = File.join(upload_dir, timestamped)
      data = doc.download

      File.binwrite(path, data)

      size = doc.byte_size < 1024 ? "#{doc.byte_size}B" : doc.byte_size < 1_048_576 ? "#{(doc.byte_size / 1024.0).round(1)}KB" : "#{(doc.byte_size / 1_048_576.0).round(1)}MB"
      result = { path: path, filename: doc.filename.to_s, size: size }

      # Tell agents the right tool for each file type
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

  def build_image_blocks(images)
    images.filter_map do |image|
      next unless image.content_type.start_with?("image/")

      data = Base64.strict_encode64(image.download)
      {
        type: "image",
        source: {
          type: "base64",
          media_type: image.content_type,
          data: data
        }
      }
    end
  end

  def build_team_context(agent:)
    teammates = @team.agents.enabled.where.not(id: agent.id).pluck(:name)

    parts = []
    parts << "You are #{agent.name} — a team member in a group chat. You have your own personality, opinions, and expertise."
    parts << "Talk like a real person on a team. Be yourself. Be concise."
    parts << ""
    parts << "Your teammates: #{teammates.map { |n| "@#{n}" }.join(", ")}."
    parts << "The human who created your team: @god."
    parts << ""
    parts << "How this chat works:"
    parts << "- Messages show as [Name]: message"
    parts << "- When you address a teammate by name, ALWAYS use @Name (e.g. @#{teammates.first || 'Bobby'}) — never just their bare name"
    parts << "- @team = everyone, @god = the human"
    parts << "- You don't have to @mention in every message — just when it's natural"
    parts << ""
    parts << "Be a teammate, not a bot. Respond when it's relevant to you. Keep it short."

    if @team.soul.present?
      parts << ""
      parts << @team.soul
    end

    parts.join("\n")
  end

  # Strip self-referencing name prefixes that LLMs echo back
  # e.g. "[Chad]: Hello!" → "Hello!", "[Chad] Hello" → "Hello"
  # Also handles nested: "[Chad]: [Chad]: Hello!" → "Hello!"
  def strip_self_name_prefix(content, agent)
    return content if content.blank?

    name = Regexp.escape(agent.name)
    # Repeatedly strip leading [Name]: or [Name] patterns (handles nested echoing)
    loop do
      stripped = content.sub(/\A\s*\[#{name}\]\s*:?\s*/i, "")
      break if stripped == content
      content = stripped
    end
    content
  end

  def resolve_tools(agent)
    assigned = agent.agent_tools.includes(:tool).map(&:tool).select(&:enabled?)
    return assigned if assigned.any?
    Tool.enabled.builtin.to_a
  end

  def track_usage(agent:, session: nil, usage:)
    return if usage.blank?
    input_tokens = usage[:input_tokens] || 0
    output_tokens = usage[:output_tokens] || 0
    UsageRecord.create(
      agent:,
      session: session,
      provider: agent.model_provider,
      llm_model: agent.llm_model,
      input_tokens:,
      output_tokens:,
      cost_cents: CostEstimator.estimate(model: agent.llm_model, input_tokens:, output_tokens:)
    )
  rescue StandardError => e
    Rails.logger.warn("TeamChat usage tracking failed: #{e.message}")
  end

  # Cost estimation moved to CostEstimator service

  def broadcast_error(agent:, error:)
    ActionCable.server.broadcast(@channel, {
      type: "error",
      agent_id: agent.id,
      agent_name: agent.name,
      content: "#{agent.name} error: #{error}"
    })
  end
end
