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
    parts << "Heartbeat check-in. Time: #{Time.current.strftime('%A %B %-d, %Y %I:%M %p %Z')}."

    standing, temporary = tasks.partition { |t| t["protected"] == true }

    if standing.any?
      parts << "\nStanding checks (do not remove):"
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
    parts << "\nReply HEARTBEAT_OK if nothing needs attention."

    parts.join("\n")
  end

  def build_light_prompt(tasks, custom)
    parts = []
    parts << "Heartbeat check-in. Time: #{Time.current.strftime('%A %B %-d, %Y %I:%M %p %Z')}."

    standing, temporary = tasks.partition { |t| t["protected"] == true }

    if standing.any?
      parts << "\nStanding checks (do not remove):"
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
end
