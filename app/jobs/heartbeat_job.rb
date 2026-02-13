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

    result = Sessions::Chat.call(session: session, message: prompt, agent: agent)

    # Restore model
    if config["model"].present? && config["model"] != original_model
      agent.update_column(:llm_model, original_model)
    end

    return unless result.success?

    reply = result.data[:reply].to_s.strip
    return if reply.blank? || reply.match?(/\AHEARTBEAT_OK\z/i)

    ActionCable.server.broadcast(
      "session_#{session.session_key}",
      { type: "heartbeat", content: reply, timestamp: Time.current.iso8601 }
    )
  rescue StandardError => e
    Rails.logger.error("[Heartbeat] Failed: #{e.message}")
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
