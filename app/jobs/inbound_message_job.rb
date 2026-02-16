# frozen_string_literal: true

class InboundMessageJob < ApplicationJob
  queue_as :default

  def perform(inbound_message_id)
    message = InboundMessage.find(inbound_message_id)
    channel = message.channel
    text = message.content.to_s.strip
    sender = message.sender

    # For Slack channels, use the new MessageRouter
    if channel.channel_type == "slack"
      route_with_message_router(message:, channel:, text:, sender:)
    else
      # Legacy routing for other channel types
      route_with_legacy_mentions(message:, channel:, text:, sender:)
    end
  rescue StandardError => e
    Rails.logger.error("[InboundMessage] Failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
  end

  private

  # ─── New Slack Routing ─────────────────────────────────────────
  
  def route_with_message_router(message:, channel:, text:, sender:)
    router_result = Channels::MessageRouter.call(
      channel: channel,
      message: message
    )
    
    unless router_result.success?
      Rails.logger.error("[InboundMessage] MessageRouter failed: #{router_result.error}")
      return
    end
    
    agent = router_result.data[:agent]
    unless agent
      Rails.logger.warn("[InboundMessage] No agent found for Slack channel #{channel.id}")
      return
    end
    
    thread_id = extract_thread_id(message)
    
    # Route to agent
    route_to_agent_with_thread_tracking(
      agent: agent,
      message: text,
      channel: channel,
      sender: sender,
      thread_id: thread_id
    )
  end
  
  def route_with_legacy_mentions(message:, channel:, text:, sender:)
    # Parse @mentions from the message
    mentioned_team, mentioned_agent, clean_text = parse_mentions(text)

    # Route to the right destination
    if mentioned_team
      route_to_team(team: mentioned_team, message: clean_text, channel:, sender:)
    elsif mentioned_agent
      route_to_agent(agent: mentioned_agent, message: clean_text, channel:, sender:)
    elsif default_team(channel)
      route_to_team(team: default_team(channel), message: text, channel:, sender:)
    elsif default_agent(channel)
      route_to_agent(agent: default_agent(channel), message: text, channel:, sender:)
    else
      Rails.logger.warn("[InboundMessage] No routing target for channel #{channel.id}")
    end
  end
  
  def route_to_agent_with_thread_tracking(agent:, message:, channel:, sender:, thread_id:)
    session = find_or_create_session(agent:, channel:, sender:)

    # Process hashtag actions before LLM
    hashtag_result = HashtagActions::Processor.call(
      message: message,
      agent: agent,
      session: session
    )

    if hashtag_result.bypass_llm
      # Hashtag handled everything — send response directly
      if hashtag_result.response.present?
        send_agent_response(
          agent: agent,
          content: hashtag_result.response,
          channel: channel,
          sender: sender,
          thread_id: thread_id
        )
      end
      return
    end

    effective_message = hashtag_result.clean_message.presence || message
    result = Sessions::Chat.call(session: session, message: effective_message, agent: agent)

    if result.success? && result.data[:reply].present?
      reply = result.data[:reply]
      # Prepend hashtag response if any
      reply = "#{hashtag_result.response}\n\n#{reply}" if hashtag_result.response.present?

      send_agent_response(
        agent: agent,
        content: reply,
        channel: channel,
        sender: sender,
        thread_id: thread_id
      )
      
      # Track thread ownership if this is a threaded response
      if thread_id.present?
        ChannelThread.claim_thread(
          channel: channel,
          agent: agent,
          thread_id: thread_id
        )
      end
    end
  end
  
  def send_agent_response(agent:, content:, channel:, sender:, thread_id: nil)
    adapter = Channels::Registry.adapter_for(channel)
    
    # For Slack, send with agent context and no name prefix (bot identity handles it)
    if channel.channel_type == "slack"
      options = {}
      options[:thread_ts] = thread_id if thread_id.present?
      
      adapter.send_message(
        to: sender,
        content: content,
        agent: agent,
        **options
      )
    else
      # For other channels, keep the [AgentName] prefix
      adapter.send_message(
        to: sender,
        content: "[#{agent.name}] #{content}"
      )
    end
  end
  
  def extract_thread_id(message)
    message.metadata&.dig("thread_ts") || message.metadata&.dig(:thread_ts)
  end

  # ─── Legacy Mention Parsing ────────────────────────────────────────────

  def parse_mentions(text)
    # @TeamName or @AgentName at the start of message
    if text =~ /\A@(\S+)\s*(.*)/m
      name = $1
      rest = $2.strip

      # Check teams first
      team = Team.where("LOWER(name) = ?", name.downcase).first
      return [ team, nil, rest ] if team

      # Then agents
      agent = Agent.visible.enabled.where("LOWER(name) = ?", name.downcase).first
      # Try with spaces (e.g., @DevOps_Engineer → "DevOps Engineer")
      agent ||= Agent.visible.enabled.where("LOWER(REPLACE(name, ' ', '_')) = ?", name.downcase).first
      return [ nil, agent, rest ] if agent
    end

    [ nil, nil, text ]
  end

  # ─── Team Routing ───────────────────────────────────────────────

  def route_to_team(team:, message:, channel:, sender:)
    # Find or create a team chat session for this sender
    tcs = TeamChatSession.find_or_create_by!(
      team: team,
      session_key: "channel-#{channel.id}-#{sender}"
    ) do |s|
      s.user = User.first # System user for channel messages
      s.title = "#{channel.channel_type.titleize} — #{sender}"
    end

    # Store the message
    TeamChatMessage.create!(
      team_chat_session: tcs,
      sender_type: "external",
      sender_id: 0,
      content: message,
      metadata: { sender: sender, channel_type: channel.channel_type }
    )

    # Determine which agents should respond
    # @team = all agents, @AgentName = specific, default = all
    agents = team.agents.enabled

    agents.each do |agent|
      process_team_agent_response(
        agent:, team:, tcs:, message:, channel:, sender:
      )
    end
  end

  def process_team_agent_response(agent:, team:, tcs:, message:, channel:, sender:)
    # Get or create per-agent session within this team chat
    session = Session.find_or_create_by!(
      agent: agent,
      team_chat_session: tcs
    ) do |s|
      s.session_key = "teamchat-#{tcs.id}-agent-#{agent.id}"
      s.title = "#{team.name} — #{agent.name}"
      s.status = "active"
    end

    # Build context: team info + recent messages
    context = build_team_context(agent:, team:, tcs:)

    result = Sessions::Chat.call(
      session: session,
      message: "#{context}\n\nNew message from external user: #{message}",
      agent: agent
    )

    return unless result.success? && result.data[:reply].present?

    reply = result.data[:reply]

    # Store agent response
    TeamChatMessage.create!(
      team_chat_session: tcs,
      sender_type: "Agent",
      sender_id: agent.id,
      target_agent_id: nil,
      content: reply
    )

    # Send back via channel with agent name prefix
    adapter = Channels::Registry.adapter_for(channel)
    adapter.send_message(
      to: sender,
      content: "[#{agent.name}] #{reply}"
    )
  rescue StandardError => e
    Rails.logger.error("[InboundMessage] Agent #{agent.name} failed: #{e.message}")
  end

  def build_team_context(agent:, team:, tcs:)
    recent = TeamChatMessage.where(team_chat_session: tcs)
                            .order(created_at: :desc)
                            .limit(10)
                            .reverse

    return "" if recent.empty?

    lines = recent.map do |msg|
      name = if msg.sender_type == "Agent"
               Agent.find_by(id: msg.sender_id)&.name || "Agent"
      else
               "User"
      end
      "[#{name}] #{msg.content.truncate(200)}"
    end

    "Recent conversation:\n#{lines.join("\n")}"
  end

  # ─── Single Agent Routing ──────────────────────────────────────

  def route_to_agent(agent:, message:, channel:, sender:)
    session = find_or_create_session(agent:, channel:, sender:)

    # Process hashtag actions before LLM
    hashtag_result = HashtagActions::Processor.call(
      message: message,
      agent: agent,
      session: session
    )

    if hashtag_result.bypass_llm
      # Hashtag handled everything — send response directly
      if hashtag_result.response.present?
        adapter = Channels::Registry.adapter_for(channel)
        adapter.send_message(to: sender, content: "[#{agent.name}] #{hashtag_result.response}")
      end
      return
    end

    effective_message = hashtag_result.clean_message.presence || message
    result = Sessions::Chat.call(session: session, message: effective_message, agent: agent)

    if result.success? && result.data[:reply].present?
      reply = result.data[:reply]
      # Prepend hashtag response if any
      reply = "#{hashtag_result.response}\n\n#{reply}" if hashtag_result.response.present?

      adapter = Channels::Registry.adapter_for(channel)
      adapter.send_message(
        to: sender,
        content: "[#{agent.name}] #{reply}"
      )
    end
  end

  def find_or_create_session(agent:, channel:, sender:)
    key = "channel-#{channel.id}-#{sender}-agent-#{agent.id}"
    Session.find_or_create_by!(session_key: key) do |s|
      s.agent = agent
      s.title = "#{channel.channel_type.titleize} — #{sender}"
      s.status = "active"
    end
  end

  # ─── Defaults ──────────────────────────────────────────────────

  def default_team(channel)
    team_id = channel.config&.dig("default_team_id")
    Team.find_by(id: team_id) if team_id.present?
  end

  def default_agent(channel)
    agent_id = channel.config&.dig("default_agent_id")
    return Agent.find_by(id: agent_id) if agent_id.present?

    Agent.visible.enabled.first
  end
end
