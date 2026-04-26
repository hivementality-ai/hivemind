# frozen_string_literal: true

class InboundMessageJob < ApplicationJob
  queue_as :agents

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

    # Route to agent — reply to the Slack channel where the message came from
    slack_channel_id = message.metadata&.dig("channel_id")

    route_to_agent_with_thread_tracking(
      agent: agent,
      message: text,
      channel: channel,
      sender: sender,
      thread_id: thread_id,
      slack_channel_id: slack_channel_id
    )
  end

  def route_with_legacy_mentions(message:, channel:, text:, sender:)
    # Parse @mentions from the message
    mentioned_team, mentioned_agent, clean_text = parse_mentions(text)

    # Extract reply target channel for platforms where sender != channel
    # (e.g., Discord sender is a user ID but replies go to a channel ID)
    reply_channel_id = message.metadata&.dig("channel_id")
    thread_id = message.metadata&.dig("thread_id")

    # Route to the right destination
    if mentioned_team
      route_to_team(team: mentioned_team, message: clean_text, channel:, sender:, reply_channel_id: reply_channel_id)
    elsif mentioned_agent
      route_to_agent(agent: mentioned_agent, message: clean_text, channel:, sender:, reply_channel_id: reply_channel_id, thread_id: thread_id)
    elsif default_team(channel)
      route_to_team(team: default_team(channel), message: text, channel:, sender:, reply_channel_id: reply_channel_id)
    elsif default_agent(channel)
      route_to_agent(agent: default_agent(channel), message: text, channel:, sender:, reply_channel_id: reply_channel_id, thread_id: thread_id)
    else
      Rails.logger.warn("[InboundMessage] No routing target for channel #{channel.id}")
    end
  end

  def route_to_agent_with_thread_tracking(agent:, message:, channel:, sender:, thread_id:, slack_channel_id: nil)
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
          thread_id: thread_id,
          slack_channel_id: slack_channel_id
        )
      end
      return
    end

    effective_message = hashtag_result.clean_message.presence || message
    result = Sessions::Chat.call(session: session, message: effective_message, agent: agent)

    if result.success? && result.data[:content].present?
      reply = result.data[:content]
      # Prepend hashtag response if any
      reply = "#{hashtag_result.response}\n\n#{reply}" if hashtag_result.response.present?

      send_agent_response(
        agent: agent,
        content: reply,
        channel: channel,
        sender: sender,
        thread_id: thread_id,
        slack_channel_id: slack_channel_id
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

  def send_agent_response(agent:, content:, channel:, sender:, thread_id: nil, team_context: false, slack_channel_id: nil, reply_channel_id: nil)
    adapter = Channels::Registry.adapter_for(channel)
    formatted = format_agent_message(agent:, content:, channel:, team_context:)

    case channel.channel_type
    when "slack"
      # Reply to the Slack channel/DM where the message came from, not the user ID
      target = slack_channel_id || reply_channel_id || sender
      options = {}
      options[:thread_ts] = thread_id if thread_id.present?

      adapter.send_message(
        to: target,
        content: formatted,
        agent: agent,
        **options
      )
    when "discord"
      # Discord sender is a user ID, but messages must be sent to a channel ID
      target = reply_channel_id || sender
      options = {}
      options[:thread_id] = thread_id if thread_id.present?

      adapter.send_message(
        to: target,
        content: formatted,
        agent: agent,
        **options
      )
    else
      adapter.send_message(to: sender, content: formatted)
    end
  end

  # Only prefix with [AgentName] when multiple agents could be responding (team context)
  def format_agent_message(agent:, content:, channel:, team_context: false)
    return content if channel.channel_type == "slack" # Slack uses bot identity
    return "[#{agent.name}] #{content}" if team_context

    content
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

  def route_to_team(team:, message:, channel:, sender:, reply_channel_id: nil)
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
        agent:, team:, tcs:, message:, channel:, sender:, reply_channel_id: reply_channel_id
      )
    end
  end

  def process_team_agent_response(agent:, team:, tcs:, message:, channel:, sender:, reply_channel_id: nil)
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

    return unless result.success? && result.data[:content].present?

    reply = result.data[:content]

    # Store agent response
    TeamChatMessage.create!(
      team_chat_session: tcs,
      sender_type: "Agent",
      sender_id: agent.id,
      target_agent_id: nil,
      content: reply
    )

    # Send back via channel with agent name prefix (team context)
    send_agent_response(
      agent: agent,
      content: reply,
      channel: channel,
      sender: sender,
      team_context: true,
      reply_channel_id: reply_channel_id
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

  def route_to_agent(agent:, message:, channel:, sender:, reply_channel_id: nil, thread_id: nil)
    session = find_or_create_session(agent:, channel:, sender:)

    # Process hashtag actions before LLM
    hashtag_result = HashtagActions::Processor.call(
      message: message,
      agent: agent,
      session: session
    )

    if hashtag_result.bypass_llm
      if hashtag_result.response.present?
        send_agent_response(agent: agent, content: hashtag_result.response, channel: channel, sender: sender, reply_channel_id: reply_channel_id, thread_id: thread_id)
      end
      return
    end

    effective_message = hashtag_result.clean_message.presence || message
    result = Sessions::Chat.call(session: session, message: effective_message, agent: agent)

    reply = result.data[:content] if result.success?

    if reply.present?
      reply = "#{hashtag_result.response}\n\n#{reply}" if hashtag_result.response.present?
      send_agent_response(agent: agent, content: reply, channel: channel, sender: sender, reply_channel_id: reply_channel_id, thread_id: thread_id)
    else
      Rails.logger.warn("[InboundMessage] No reply to send back")
    end
  end

  def find_or_create_session(agent:, channel:, sender:)
    key = "channel-#{channel.id}-#{sender}-agent-#{agent.id}"
    Session.find_or_create_by!(session_key: key) do |s|
      s.agent = agent
      s.title = "#{channel.channel_type.titleize} — #{sender}"
      s.status = "active"

      # Track origin for WhatsApp so responses auto-route back
      if channel.channel_type == "whatsapp"
        s.origin_channel_type = "whatsapp"
        s.origin_channel_id = channel.id
        s.origin_sender = sender
      end
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
