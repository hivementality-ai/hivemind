# frozen_string_literal: true

class HeartbeatJob < ApplicationJob
  queue_as :default

  def perform
    config = load_config
    return unless config["enabled"]

    # Check if due
    last_run = Setting.get("heartbeat_last_run")
    interval = (config["interval_minutes"] || 30).to_i.minutes

    if last_run.present? && Time.parse(last_run) > interval.ago
      return # Not due yet
    end

    Setting.set("heartbeat_last_run", Time.current.iso8601)

    # Use the hidden system assistant
    agent = Agent.system_assistant

    # Override model and provider if user picked one
    original_model = agent.llm_model
    original_provider = agent.model_provider
    if config["model"].present?
      agent.update_column(:llm_model, config["model"])
      provider = config["provider"].presence || provider_for_model(config["model"])
      agent.update_column(:model_provider, provider) if provider.present?
    end

    session = Session.find_or_create_by!(
      agent: agent,
      title: "🫀 Heartbeat"
    ) do |s|
      s.session_key = "heartbeat-system"
      s.status = "active"
      s.metadata = { type: "heartbeat" }
    end

    prompt = build_prompt(config)

    Rails.logger.info("[Heartbeat] Running with model #{agent.llm_model} via #{agent.model_provider}")

    started_at = Time.current
    result = Sessions::Chat.call(session: session, message: prompt, agent: agent)
    duration_ms = ((Time.current - started_at) * 1000).to_i

    # Restore original model and provider
    if config["model"].present? && config["model"] != original_model
      agent.update_column(:llm_model, original_model)
      agent.update_column(:model_provider, original_provider) if original_provider.present?
    end

    usage = result&.data&.dig(:usage) || {}
    reply = result&.success? ? result.data[:content].to_s.strip : nil
    is_ok = reply.blank? || reply.match?(/\AHEARTBEAT_OK\z/i)

    # Track the run
    HeartbeatRun.create!(
      agent: agent,
      session: session,
      status: result&.success? ? (is_ok ? "ok" : "action_taken") : "error",
      summary: result&.success? ? reply&.truncate(2000) : result&.error&.truncate(2000),
      input_tokens: usage[:input_tokens] || 0,
      output_tokens: usage[:output_tokens] || 0,
      duration_ms: duration_ms,
      model: agent.llm_model,
      metadata: { tasks_count: load_tasks.size }
    )

    return if !result&.success? || is_ok

    ActionCable.server.broadcast(
      "session_#{session.session_key}",
      { type: "heartbeat", content: reply, timestamp: Time.current.iso8601 }
    )
    # Run project coordination on every heartbeat tick
    Projects::Coordinator.call if Project.active_or_blocked.any?

  rescue StandardError => e
    Rails.logger.error("[Heartbeat] Failed: #{e.message}")

    # Track error runs too
    HeartbeatRun.create(
      agent: Agent.system_assistant,
      status: "error",
      summary: e.message.truncate(2000),
      duration_ms: 0,
      metadata: { backtrace: e.backtrace&.first(3) }
    )
  end

  private

  def load_config
    raw = Setting.get("heartbeat")
    return {} unless raw
    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  # Derive the adapter_type (provider) for a given model ID by checking which
  # enabled ProviderConfig has that model in its model_definitions.
  def provider_for_model(model_id)
    ProviderConfig.enabled_providers.find do |pc|
      (pc.model_definitions || []).any? { |m| m["id"] == model_id }
    end&.adapter_type
  end

  def build_prompt(config)
    tasks = load_tasks
    custom = config["prompt"]

    if config["light_context"]
      build_light_prompt(tasks, custom)
    else
      build_full_prompt(tasks, custom)
    end
  end

  def build_full_prompt(tasks, custom)
    parts = []
    parts << "This is your periodic heartbeat check-in. You are a monitor and delegator — assess and route, do not execute directly."
    parts << "First, search your memories for context from previous heartbeats using the memory_search tool."
    parts << "After completing checks, save important findings to memory so you remember them next time."

    standing, temporary = tasks.partition { |t| t["protected"] == true }

    if standing.any?
      parts << "\n## Standing Monitors (run every heartbeat — do not remove these)"
      standing.each_with_index do |t, i|
        parts << "#{i + 1}. #{t["task"]}"
      end
    end

    if temporary.any?
      parts << "\n## One-Off Tasks (handle then remove via heartbeat_write remove)"
      temporary.each_with_index do |t, i|
        parts << "#{i + 1}. #{t["task"]}"
      end
      parts << "Remove each one-off task after handling it using: heartbeat_write action=remove"
    end

    parts << "\n#{custom}" if custom.present?

    # Include open task board context so the monitor can assess status
    open_tasks = Task.open.by_priority.includes(:assigned_to_agent).limit(20)
    if open_tasks.any?
      parts << "\n## Team Task Board"
      open_tasks.each { |t| parts << "  - #{t.to_summary}" }
    end

    # Highlight overdue tasks — these need delegation
    overdue = open_tasks.select(&:overdue?)
    if overdue.any?
      parts << "\n## Overdue — Delegate These"
      overdue.each { |t| parts << "  - #{t.to_summary}" }
    end

    # Team-only delegation targets
    team_agents = team_delegation_targets
    if team_agents.any?
      parts << "\n## Your Team (delegate only to these agents)"
      team_agents.each { |name, role| parts << "- #{name} (#{role})" }
    end

    parts << "\nIf nothing needs attention, reply with exactly: HEARTBEAT_OK"

    parts.join("\n")
  end

  def build_light_prompt(tasks, custom)
    parts = []
    parts << "Heartbeat check-in. Monitor and delegate — do not execute. Tools: memory_search, delegate, task_manager, heartbeat_write."

    standing, temporary = tasks.partition { |t| t["protected"] == true }

    if standing.any?
      parts << "\nStanding monitors (do not remove):"
      standing.each_with_index do |t, i|
        parts << "#{i + 1}. #{t["task"]}"
      end
    end

    if temporary.any?
      parts << "\nOne-off tasks (remove after handling):"
      temporary.each_with_index do |t, i|
        parts << "#{i + 1}. #{t["task"]}"
      end
    end

    parts << "\n#{custom}" if custom.present?

    team_agents = team_delegation_targets
    if team_agents.any?
      parts << "\nTeam (delegate only to these):"
      team_agents.each { |name, role| parts << "- #{name} (#{role})" }
    end

    parts << "\nReply HEARTBEAT_OK if nothing needs attention."

    parts.join("\n")
  end

  def load_tasks
    raw = Setting.get("heartbeat_tasks")
    return [] unless raw
    JSON.parse(raw)
  rescue JSON::ParserError
    []
  end

  # Returns [name, role] pairs for agents that belong to a team.
  # The heartbeat delegates to team members only — not every visible agent.
  def team_delegation_targets
    Agent.visible.enabled.where.not(team_id: nil).pluck(:name, :role)
  end
end
