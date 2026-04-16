# frozen_string_literal: true

module Tools
  class TalkToTeammateExecutor < BaseExecutor
    def call
      teammate_name = input["teammate"].to_s.strip
      message = input["message"].to_s.strip

      return ServiceResponse.failure(error: "No teammate name provided") if teammate_name.empty?
      return ServiceResponse.failure(error: "No message provided") if message.empty?

      session = config[:session]
      return ServiceResponse.failure(error: "No session context available") unless session

      team_id = session.metadata&.dig("team_id")
      team_chat_session = TeamChatSession.find_by(id: session.metadata&.dig("team_chat_session_id"))
      team = team_chat_session&.team || Team.find_by(id: team_id)
      return ServiceResponse.failure(error: "No team context available") unless team

      # Look up target agent
      target = team.agents.enabled.where("LOWER(name) = ?", teammate_name.downcase).first
      return ServiceResponse.failure(error: "Teammate '#{teammate_name}' not found. Available: #{available_teammates(team)}") unless target

      # Guard: no self-talk
      if agent && target.id == agent.id
        return ServiceResponse.failure(error: "You can't talk to yourself. Choose a different teammate.")
      end

      # Guard: depth limit
      depth = config[:team_chat_depth] || 0
      if depth <= 0
        return ServiceResponse.failure(error: "Conversation depth limit reached. Respond directly instead of calling another teammate.")
      end

      # Guard: prevent cycles (A→B→A)
      active_ids = config[:active_agent_ids] || []
      if active_ids.include?(target.id)
        return ServiceResponse.failure(error: "#{target.name} is already in this conversation chain. Respond directly instead.")
      end

      channel = config[:team_chat_channel] || "team_chat_#{team_chat_session&.id}"

      # Broadcast outgoing message
      ActionCable.server.broadcast(channel, {
        type: "agent_to_agent",
        from_agent_id: agent&.id,
        from_agent_name: agent&.name,
        to_agent_id: target.id,
        to_agent_name: target.name,
        content: message
      })

      # Save outgoing message to team chat
      outgoing_msg = team_chat_session&.team_chat_messages&.create!(
        sender_type: "agent",
        sender_id: agent&.id,
        content: message,
        metadata: { agent_to_agent: true, to_agent_id: target.id, to_agent_name: target.name }
      )

      # Get target agent's session in this team chat
      target_session = team_chat_session&.session_for(target)
      return ServiceResponse.failure(error: "Could not create session for #{target.name}") unless target_session

      # Resolve provider for target agent
      resolver = Providers::Resolver.call(provider_name: target.model_provider, agent: target)
      return ServiceResponse.failure(error: "Provider error for #{target.name}: #{resolver.error}") unless resolver.success?

      adapter = resolver.data[:adapter]

      # Broadcast thinking indicator
      ActionCable.server.broadcast(channel, {
        type: "thinking",
        agent_id: target.id,
        agent_name: target.name
      })

      # Build messages for the target agent
      target_messages = build_target_messages(target:, team_chat_session:, incoming_message: message)

      # Append to target's transcript
      target_session.append_transcript({ "role" => "user", "content" => "[#{agent&.name}]: #{message}" })

      # Resolve tools for target
      target_tools = resolve_tools(target, team)
      # Remove talk_to_teammate if depth would be exhausted
      next_depth = depth - 1
      if next_depth <= 0
        target_tools = target_tools.reject { |t| t.is_a?(SystemTool) && t.name == "talk_to_teammate" }
      end

      # Build LLM options
      llm_options = { model: target.llm_model, max_tokens: target.max_output_tokens || 8192 }
      llm_options.merge!(target.inference_options)

      broadcast_extras = { agent_id: target.id, agent_name: target.name }

      # Execute target agent synchronously via ToolLoop
      result = Agents::ToolLoop.call(
        adapter: adapter,
        agent: target,
        session: target_session,
        messages: target_messages,
        tools: target_tools,
        channel: channel,
        options: llm_options,
        broadcast_extras: broadcast_extras,
        extra_config: {
          team_chat_depth: next_depth,
          active_agent_ids: active_ids + [ agent&.id, target.id ].compact,
          team_chat_channel: channel,
          session: target_session
        }
      )

      response_content = result&.data&.dig(:content).to_s
      response_content = "_(No response generated)_" if response_content.blank?

      # Strip self-name prefix
      response_content = response_content.sub(/\A\s*\[[^\]]+\]\s*:?\s*/i, "")

      # Persist to target's transcript
      target_session.append_transcript({ "role" => "assistant", "content" => response_content })

      # Save response to team chat
      team_chat_session&.team_chat_messages&.create!(
        sender_type: "agent",
        sender_id: target.id,
        content: response_content,
        metadata: { agent_to_agent: true, from_agent_id: agent&.id, from_agent_name: agent&.name }
      )

      # Broadcast response
      ActionCable.server.broadcast(channel, {
        type: "agent_to_agent_response",
        from_agent_id: target.id,
        from_agent_name: target.name,
        to_agent_id: agent&.id,
        to_agent_name: agent&.name,
        content: response_content
      })

      ActionCable.server.broadcast(channel, {
        type: "agent_done",
        agent_id: target.id,
        agent_name: target.name,
        content: response_content
      })

      ServiceResponse.success(data: {
        output: "#{target.name} responded:\n\n#{response_content.truncate(3000)}"
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to talk to teammate: #{e.message}")
    end

    private

    def available_teammates(team)
      team.agents.enabled.where.not(id: agent&.id).pluck(:name).join(", ")
    end

    def build_target_messages(target:, team_chat_session:, incoming_message:)
      messages = []

      # System prompt
      system_blocks = target.respond_to?(:system_prompt_blocks) ? target.system_prompt_blocks : [ { type: "text", text: target.full_system_prompt.presence || "You are #{target.name}" } ]

      # Team context
      team = team_chat_session.team
      teammates = team.agents.enabled.where.not(id: target.id).pluck(:name)
      human_name = team_chat_session.user&.email&.split("@")&.first || "god"

      team_context = [
        "You are #{target.name} — a team member in a group chat.",
        "Your teammates: #{teammates.join(", ")}.",
        "The human: #{human_name}.",
        "",
        "#{agent&.name} is asking you a direct question via the talk_to_teammate tool.",
        "Respond concisely and helpfully. Your response will be sent back to #{agent&.name}.",
        "Never use @mentions in your responses — just use names naturally."
      ].join("\n")

      system_blocks << { type: "text", text: team_context }
      messages << { role: "system", content: system_blocks }

      # Recent chat history for context
      recent = team_chat_session.team_chat_messages.chronological.last(5)
      recent.each do |msg|
        if msg.from_agent? && msg.sender_id == target.id
          messages << { role: "assistant", content: msg.content }
        else
          sender_name = if msg.from_user?
            User.find_by(id: msg.sender_id)&.email&.split("@")&.first || "User"
          else
            Agent.find_by(id: msg.sender_id)&.name || "Agent"
          end
          messages << { role: "user", content: "[#{sender_name}]: #{msg.content}" }
        end
      end

      # The incoming message
      messages << { role: "user", content: "[#{agent&.name}]: #{incoming_message}" }

      messages
    end

    def resolve_tools(target, team)
      assigned = target.agent_tools.includes(:tool).map(&:tool).select(&:enabled?)
      tools = assigned.any? ? assigned : Tool.enabled.builtin.to_a

      # Remove delegate/delegation_status — these spawn separate sessions and lose
      # team chat context. talk_to_teammate is the correct tool here.
      tools = tools.reject { |t| t.respond_to?(:executor_type) && %w[delegate delegation_status].include?(t.executor_type) }

      # Inject system tools
      tools << SystemTool::LOAD_SKILL if target.skills.enabled.any?

      # Inject talk_to_teammate if there are other teammates
      teammates = team.agents.enabled.where.not(id: target.id)
      tools << SystemTool::TALK_TO_TEAMMATE if teammates.any?

      tools
    end
  end
end
