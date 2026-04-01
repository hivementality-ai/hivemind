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

    # Override model if user picked one
    original_model = agent.llm_model
    if config["model"].present?
      agent.update_column(:llm_model, config["model"])
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

    Rails.logger.info("[Heartbeat] Running with model #{agent.llm_model}")

    started_at = Time.current
    result = Sessions::Chat.call(session: session, message: prompt, agent: agent)
    duration_ms = ((Time.current - started_at) * 1000).to_i

    # Restore model
    if config["model"].present? && config["model"] != original_model
      agent.update_column(:llm_model, original_model)
    end

    usage = result&.data&.dig(:usage) || {}
    reply = result&.success? ? result.data[:reply].to_s.strip : nil
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

  def build_prompt(config)
    tasks = load_tasks
    custom = config["prompt"]

    parts = []
    parts << "This is your periodic heartbeat check-in."
    parts << "First, check your memories for context from previous heartbeats using the memory_search tool."
    parts << "After completing tasks, save important findings to memory so you remember them next time."

    if tasks.any?
      parts << "\nYour checklist:"
      tasks.each_with_index do |t, i|
        parts << "#{i + 1}. #{t["task"]}"
      end
      parts << "\nWork through each task. Report what you find."
    end

    parts << "\n#{custom}" if custom.present?

    # Include open task board context so agents can act on pending work
    open_tasks = Task.open.by_priority.includes(:assigned_to_agent).limit(20)
    if open_tasks.any?
      parts << "\nOpen tasks on the team board (use task_manager tool to update):"
      open_tasks.each { |t| parts << "  - #{t.to_summary}" }
    end

    # Highlight overdue tasks
    overdue = open_tasks.select(&:overdue?)
    if overdue.any?
      parts << "\nOverdue tasks requiring attention:"
      overdue.each { |t| parts << "  - #{t.to_summary}" }
    end

    # Tell it who's available to delegate to
    teammates = Agent.visible.enabled.pluck(:name, :role)
    if teammates.any?
      parts << "\nAvailable teammates you can delegate to:"
      teammates.each { |name, role| parts << "- #{name} (#{role})" }
    end

    parts << "\nIf nothing needs attention, reply with exactly: HEARTBEAT_OK"

    parts.join("\n")
  end

  def load_tasks
    raw = Setting.get("heartbeat_tasks")
    return [] unless raw
    JSON.parse(raw)
  rescue JSON::ParserError
    []
  end
end
