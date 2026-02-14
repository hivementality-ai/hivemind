# frozen_string_literal: true

class TeamChatJob < ApplicationJob
  queue_as :default

  # Process a message in a team chat — route to targeted agent(s), handle responses,
  # and trigger any @mentions in agent responses (chain reactions).
  def perform(team_chat_session_id, message_id, responding_agent_id: nil)
    @session = TeamChatSession.find(team_chat_session_id)
    @team = @session.team
    @channel = "team_chat_#{@session.id}"
    message = TeamChatMessage.find(message_id)

    # Determine which agents should respond
    agents_to_respond = if responding_agent_id
                          # This is a chain reaction — specific agent was @mentioned by another agent
                          [Agent.find(responding_agent_id)]
                        elsif message.target_agent_id
                          # User @mentioned a specific agent
                          [message.target_agent]
                        else
                          # No @mention or @team — all enabled team agents respond
                          @team.agents.enabled.order(:name).to_a
                        end

    agents_to_respond.each do |agent|
      respond_as_agent(agent:, trigger_message: message)
    end
  end

  private

  def respond_as_agent(agent:, trigger_message:)
    # Get or create persistent session for this agent in this team chat
    @agent_session = @session.session_for(agent)

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

    # Persist the triggering message to the agent's session
    sender = trigger_message.from_user? ? "user" : (Agent.find_by(id: trigger_message.sender_id)&.name || "agent")
    @agent_session.append_transcript({ "role" => "user", "content" => "[#{sender}]: #{trigger_message.content}" })

    # Build messages with team context + agent's persistent history
    messages = build_team_messages(agent:)
    tools = resolve_tools(agent)

    begin
      full_content = +""

      if tools.any?
        result = Agents::ToolLoop.call(
          adapter:,
          agent:,
          session: @agent_session,
          messages:,
          tools:,
          channel: @channel,
          options: { model: agent.llm_model, max_tokens: 8192 },
          broadcast_extras: { agent_id: agent.id, agent_name: agent.name }
        )
        full_content = result&.data&.dig(:content).to_s
      else
        result = adapter.chat(
          messages:,
          options: { model: agent.llm_model, max_tokens: 8192 }
        ) do |chunk|
          if chunk[:type] == "content" && chunk[:content]
            full_content << chunk[:content]
            ActionCable.server.broadcast(@channel, {
              type: "token",
              agent_id: agent.id,
              agent_name: agent.name,
              content: chunk[:content]
            })
          end
        end

        if full_content.empty? && result&.success?
          full_content = result.data[:content].to_s
          ActionCable.server.broadcast(@channel, {
            type: "token",
            agent_id: agent.id,
            agent_name: agent.name,
            content: full_content
          })
        end
      end

      # Save the agent's response to team chat
      agent_message = @session.team_chat_messages.create!(
        sender_type: "agent",
        sender_id: agent.id,
        content: full_content,
        metadata: { model: agent.llm_model, provider: agent.model_provider }
      )

      # Persist to agent's individual session transcript (memory continuity)
      @agent_session.append_transcript({ "role" => "assistant", "content" => full_content })

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

      # Check if the agent @mentioned another agent — trigger chain reaction
      mentions = TeamChatMessage.extract_mentions(full_content, @team)
      mentions[:agents].reject { |a| a.id == agent.id }.each do |mentioned_agent|
        TeamChatJob.perform_later(@session.id, agent_message.id, responding_agent_id: mentioned_agent.id)
      end

    rescue StandardError => e
      broadcast_error(agent:, error: e.message)
      Rails.logger.error("TeamChatJob error (#{agent.name}): #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end
  end

  def build_team_messages(agent:)
    messages = []

    # System prompt: agent soul + team soul
    system_parts = []
    system_parts << agent.full_system_prompt if agent.full_system_prompt.present?
    system_parts << build_team_context(agent:)
    messages << { role: "system", content: system_parts.join("\n\n") }

    # Chat history — include recent team chat messages for context
    recent = @session.recent_messages(limit: 30)
    # Always include at least the last 5 messages so the agent has context
    recent = @session.team_chat_messages.chronological.last(5) if recent.size < 5
    recent.each do |msg|
      if msg.from_user?
        user = User.find_by(id: msg.sender_id)
        name = user&.email&.split("@")&.first || "User"
        messages << { role: "user", content: "[#{name}]: #{msg.content}" }
      elsif msg.from_agent?
        sender_agent = Agent.find_by(id: msg.sender_id)
        if sender_agent && sender_agent.id == agent.id
          messages << { role: "assistant", content: msg.content }
        else
          sender_name = sender_agent&.name || "Agent"
          messages << { role: "user", content: "[#{sender_name}]: #{msg.content}" }
        end
      end
    end

    messages
  end

  def build_team_context(agent:)
    teammates = @team.agents.enabled.where.not(id: agent.id).pluck(:name)
    
    parts = []
    parts << "You are in a group chat. Be concise and natural — don't introduce yourself or state your role."
    parts << "Messages from others appear as [Name]: message."
    parts << ""
    parts << "Your teammates: #{teammates.map { |n| "@#{n}" }.join(", ")}."
    parts << "Special mentions: @team (everyone responds), @god (the human who created you)."
    parts << "You don't need to @mention teammates in every message — just respond naturally."
    parts << "Only use @Name when you specifically need input or help from that teammate."
    parts << "Use @god when you need a decision or approval from the human."
    parts << ""
    parts << "Only respond when it's relevant to you. Keep it short."

    if @team.soul.present?
      parts << ""
      parts << @team.soul
    end

    parts.join("\n")
  end

  def resolve_tools(agent)
    assigned = agent.agent_tools.includes(:tool).map(&:tool).select(&:enabled?)
    return assigned if assigned.any?
    Tool.enabled.builtin.to_a
  end

  def track_usage(agent:, session: nil, usage:)
    return if usage.blank?
    UsageRecord.create(
      agent:,
      session: session,
      llm_model: agent.llm_model,
      input_tokens: usage[:input_tokens] || 0,
      output_tokens: usage[:output_tokens] || 0,
      cost_cents: 0
    )
  rescue StandardError => e
    Rails.logger.warn("TeamChat usage tracking failed: #{e.message}")
  end

  def broadcast_error(agent:, error:)
    ActionCable.server.broadcast(@channel, {
      type: "error",
      agent_id: agent.id,
      agent_name: agent.name,
      content: "#{agent.name} error: #{error}"
    })
  end
end
