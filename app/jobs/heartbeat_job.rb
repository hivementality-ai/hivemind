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

    # --- Ephemeral session: fresh context every heartbeat ---
    session = Session.create!(
      agent: agent,
      title: "🫀 Heartbeat #{Time.current.strftime('%H:%M')}",
      session_key: "heartbeat-#{SecureRandom.hex(6)}",
      status: "active",
      metadata: { type: "heartbeat" }
    )

    # Load relay summary from last successful run
    previous_summary = last_relay_summary

    prompt = build_prompt(config, previous_summary)

    Rails.logger.info("[Heartbeat] Running with model #{agent.llm_model} via #{agent.model_provider} (ephemeral session #{session.session_key})")

    started_at = Time.current
    result = Sessions::Chat.call(session: session, message: prompt, agent: agent)
    duration_ms = ((Time.current - started_at) * 1000).to_i

    # Capture the model that was actually used before restoring
    effective_model = agent.llm_model

    # Restore original model and provider
    if config["model"].present? && config["model"] != original_model
      agent.update_column(:llm_model, original_model)
      agent.update_column(:model_provider, original_provider) if original_provider.present?
    end

    usage = result&.data&.dig(:usage) || {}
    reply = result&.success? ? result.data[:content].to_s.strip : nil
    tool_history = result&.success? ? result.data[:tool_history] : nil
    is_ok = reply.blank? || reply.match?(/\AHEARTBEAT_OK\z/i)

    # Validate: if no tools were called, this is a failed heartbeat
    tool_count = tool_history&.size || 0
    if tool_count == 0 && result&.success?
      Rails.logger.warn("[Heartbeat] Model returned response with ZERO tool calls — likely fabricated results")
    end

    # Mark ephemeral session as completed
    session.update!(status: "completed")

    # Track the run (summary becomes the relay note for the next heartbeat)
    HeartbeatRun.create!(
      agent: agent,
      session: session,
      status: result&.success? ? (is_ok ? "ok" : "action_taken") : "error",
      summary: result&.success? ? reply&.truncate(2000) : result&.error&.truncate(2000),
      previous_summary: previous_summary&.truncate(2000),
      input_tokens: usage[:input_tokens] || 0,
      output_tokens: usage[:output_tokens] || 0,
      duration_ms: duration_ms,
      model: effective_model,
      metadata: { tasks_count: load_tasks.size, tool_calls_count: tool_count, tool_history: tool_history&.first(20) }
    )

    # Overwrite the system assistant's single memory with the latest summary.
    # The system assistant should only ever have one memory — each heartbeat replaces it.
    overwrite_system_memory(agent, reply) if result&.success? && reply.present?

    # Clean up old ephemeral heartbeat sessions (keep last 24h)
    cleanup_old_sessions

    return if !result&.success? || is_ok

    ActionCable.server.broadcast(
      "session_#{session.session_key}",
      { type: "heartbeat", content: reply, timestamp: Time.current.iso8601 }
    )
    # DISABLED: Projects::Coordinator was auto-kicking off milestone sessions
    # every heartbeat cycle without explicit user approval. Milestones should
    # use the task board instead — agents pick up work via task_manager, not
    # by the coordinator spawning autonomous sessions behind the scenes.
    # Re-enable once milestones are wired through the task system.
    #
    # Projects::Coordinator.call if Project.active_or_blocked.any?

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

  # Get the summary from the last successful heartbeat run.
  # This is the "relay note" — what the previous heartbeat did and observed.
  def last_relay_summary
    HeartbeatRun.where(status: %w[ok action_taken])
                .order(created_at: :desc)
                .pick(:summary)
  end

  def build_prompt(config, previous_summary = nil)
    tasks = load_tasks
    custom = config["prompt"]

    if config["light_context"]
      build_light_prompt(tasks, custom, previous_summary)
    else
      build_full_prompt(tasks, custom, previous_summary)
    end
  end

  def build_full_prompt(tasks, custom, previous_summary = nil)
    parts = []
    parts << "Heartbeat check-in. Time: #{Time.current.strftime('%A %B %-d, %Y %I:%M %p %Z')}."

    # Relay summary from previous heartbeat
    if previous_summary.present? && !previous_summary.match?(/\AHEARTBEAT_OK\z/i)
      parts << "\n--- Previous heartbeat handoff ---"
      parts << previous_summary
      parts << "--- End handoff ---"
    end

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

    parts << tool_enforcement_instructions

    parts.join("\n")
  end

  def build_light_prompt(tasks, custom, previous_summary = nil)
    parts = []
    parts << "Heartbeat check-in. Time: #{Time.current.strftime('%A %B %-d, %Y %I:%M %p %Z')}."

    # Relay summary from previous heartbeat
    if previous_summary.present? && !previous_summary.match?(/\AHEARTBEAT_OK\z/i)
      parts << "\n--- Previous heartbeat handoff ---"
      parts << previous_summary
      parts << "--- End handoff ---"
    end

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

    parts << tool_enforcement_instructions

    parts.join("\n")
  end

  # Shared instructions that enforce actual tool usage.
  # This prevents models from fabricating tool results.
  def tool_enforcement_instructions
    <<~INSTRUCTIONS

      --- CRITICAL INSTRUCTIONS ---
      You have tools available. You MUST use them. This is non-negotiable.

      ALLOWED TOOLS (only use these):
      - task_manager: Check and manage the task board. This is your primary tool.
      - memory_search: Search your memories for context.
      - heartbeat_write: Manage the heartbeat checklist.
      - project_list, project_status: READ-ONLY project awareness. Check project/milestone status to include in your handoff, but do NOT modify milestones.

      FORBIDDEN TOOLS (do NOT use these, even if available):
      - trello — We do NOT use Trello. All work tracking is done via task_manager.
      - delegate — Do NOT delegate. Moving tasks to in_progress triggers hooks that start agent sessions automatically.
      - project_update — Do not modify projects or milestones directly.
      - Any tool not listed in ALLOWED TOOLS above — ignore it completely.

      ## How the Task Board Works

      The task board has hooks. When a task is moved to `in_progress`, a hook automatically
      creates a new agent session for the assigned agent with full task context. The agent
      works through the task and moves it to `review` when done. You do NOT need to delegate
      or create sessions — just move the task.

      ## YOUR JOB (in order):

      1. **Check the board**: The default list may not return everything. Call task_manager "list"
         separately for each status you need to check: "todo", "in_progress", "review", "backlog".
         Work through them one at a time so you don't miss anything.

      2. **Kick off ready work**: For any task in "todo" status that:
         - Has an assigned agent, AND
         - Has its dependencies met (not blocked)
         → Move it to "in_progress" using task_manager with action "move". The hook system handles the rest.

      3. **Flag unassigned work**: If a "todo" task has no assigned agent, note it in your handoff.

      4. **Monitor in_progress tasks**: Check for tasks that seem stalled (in_progress for a long time).
         Note any concerns in your handoff. Do NOT move them — just report.

      5. **Handle checklist**: Complete any one-off heartbeat checklist items, then remove them with heartbeat_write.

      6. **Check projects** (if any): Call project_list / project_status to get a read on milestone progress. Include in handoff.

      ## RULES:
      - NEVER fabricate or invent tool results. If you didn't call it, you don't know.
      - A heartbeat without tool calls is INVALID.
      - Do NOT ask the user questions. Flag issues in the handoff.
      - Do NOT chase Trello, links, or tangents from the previous handoff. Stick to the checklist.
      - Stay focused: check board → move ready tasks → handle checklist → write handoff → done.

      You are running in ephemeral mode. The handoff above is your only context from the previous cycle.

      End your response with a HANDOFF SUMMARY for the next heartbeat.
      Format: 'HANDOFF: [what you did, what's pending, anything the next heartbeat should know]'
      If nothing needs attention, reply HEARTBEAT_OK.
    INSTRUCTIONS
  end

  # Replace all existing memories for the system assistant with a single
  # memory containing the latest heartbeat summary. This prevents memory
  # accumulation and ensures the assistant always has exactly one memory.
  def overwrite_system_memory(agent, summary)
    ActiveRecord::Base.transaction do
      agent.memory_entries.destroy_all
      MemoryEntry.create!(
        agent: agent,
        content: summary.truncate(2000),
        memory_type: "semantic",
        importance: 1.0,
        metadata: { source: "heartbeat", updated_at: Time.current.iso8601 }
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[Heartbeat] Memory overwrite failed: #{e.message}")
  end

  # Remove ephemeral heartbeat sessions older than 24 hours.
  # Keeps the database clean without losing recent audit trail.
  def cleanup_old_sessions
    Session.where("title LIKE ?", "🫀 Heartbeat%")
           .where(status: "completed")
           .where("created_at < ?", 24.hours.ago)
           .destroy_all
  rescue StandardError => e
    Rails.logger.warn("[Heartbeat] Session cleanup failed: #{e.message}")
  end

  def load_tasks
    raw = Setting.get("heartbeat_tasks")
    return [] unless raw
    JSON.parse(raw)
  rescue JSON::ParserError
    []
  end
end
