# frozen_string_literal: true

class SubAgentJob < ApplicationJob
  queue_as :agents

  def perform(sub_agent_task_id)
    sat = SubAgentTask.find(sub_agent_task_id)
    sat.update!(status: "running", started_at: Time.current)

    agent = sat.child_agent

    # Create isolated session for the sub-agent
    session = Session.create!(
      agent: agent,
      session_key: "sub-#{sat.task_key}",
      title: "🔀 Sub-task from #{sat.parent_agent.name}",
      status: "active",
      metadata: {
        type: "sub_agent",
        parent_task_id: sat.id,
        parent_agent: sat.parent_agent.name,
        delegation_depth: sat.depth
      }
    )

    sat.update!(child_session: session)

    # Broadcast sub-agent started
    broadcast_sub_agent_event(sat, "sub_agent_started", {
      task_key: sat.task_key,
      child_agent: agent.name,
      task: sat.task.truncate(200)
    })

    # Run the task through the agent's full pipeline (tools, memory, everything)
    result = Sessions::Chat.call(
      session: session,
      message: sat.task,
      agent: agent
    )

    if result.success?
      reply = result.data[:content].to_s
      sat.update!(
        status: "completed",
        result: reply,
        completed_at: Time.current
      )

      broadcast_sub_agent_event(sat, "sub_agent_complete", {
        task_key: sat.task_key,
        child_agent: agent.name,
        task: sat.task.truncate(100),
        result: reply.truncate(500),
        success: true,
        duration: sat.duration_seconds
      })

      persist_to_team_chat(sat, reply) if team_chat_session(sat)

      # Push notification for task completion
      WebPush::NotificationTriggers.task_completed(task: sat)

      callback_to_parent(sat, reply, success: true)
    else
      error_msg = "Sub-agent failed: #{result.error}"
      sat.update!(
        status: "failed",
        result: "Error: #{result.error}",
        completed_at: Time.current
      )

      broadcast_sub_agent_event(sat, "sub_agent_complete", {
        task_key: sat.task_key,
        child_agent: agent.name,
        task: sat.task.truncate(100),
        result: error_msg.truncate(500),
        success: false,
        duration: sat.duration_seconds
      })

      callback_to_parent(sat, error_msg, success: false)
    end
  rescue StandardError => e
    sat&.update!(status: "failed", result: "Error: #{e.message}", completed_at: Time.current)
    Rails.logger.error("[SubAgent] Task #{sub_agent_task_id} failed: #{e.message}")

    broadcast_sub_agent_event(sat, "sub_agent_complete", {
      task_key: sat&.task_key,
      child_agent: sat&.child_agent&.name,
      result: "Sub-agent error: #{e.message}".truncate(500),
      success: false
    }) if sat

    # Still try to callback on error so parent knows
    callback_to_parent(sat, "Sub-agent error: #{e.message}", success: false) if sat&.parent_session
  end

  private

  # Inject the sub-agent's result back into the parent agent's session.
  # The parent agent receives it as a new message and can act on it.
  def callback_to_parent(sat, reply, success:)
    return unless sat&.parent_session

    # Runaway chains are prevented at spawn time (Delegations::Request), so
    # every completed task can safely report back to its parent.
    status_emoji = success ? "✅" : "❌"
    duration = sat.duration_seconds ? " in #{sat.duration_seconds}s" : ""

    # Build a clear message the parent agent can parse and act on
    callback_message = <<~MSG.strip
      [Sub-agent result#{duration}] #{status_emoji} #{sat.child_agent.name} — #{sat.task.truncate(100)}

      #{reply.truncate(2000)}

      (Task ID: #{sat.task_key} | Use delegation_status for full output if truncated)
    MSG

    # Fire ChatStreamJob on the parent session so the parent agent processes the result
    ChatStreamJob.perform_later(
      sat.parent_session.id,
      callback_message,
      [] # no attachments
    )

    Rails.logger.info("[SubAgent] Callback fired to parent session #{sat.parent_session.id} for task #{sat.task_key}")
  end

  # Determine if the parent session belongs to a team chat
  def team_chat_session(sat)
    return nil unless sat&.parent_session
    sat.parent_session.team_chat_session_id.present? ? TeamChatSession.find_by(id: sat.parent_session.team_chat_session_id) : nil
  end

  # Broadcast sub-agent events to the appropriate channel
  def broadcast_sub_agent_event(sat, event_type, data)
    return unless sat&.parent_session

    tcs = team_chat_session(sat)
    channel = tcs ? "team_chat_#{tcs.id}" : "session_#{sat.parent_session.id}"

    ActionCable.server.broadcast(channel, { type: event_type, timestamp: Time.current.iso8601 }.merge(data))
  rescue StandardError => e
    Rails.logger.warn("[SubAgent] Broadcast failed: #{e.message}")
  end

  # Persist sub-agent result as a TeamChatMessage so it survives page reload
  def persist_to_team_chat(sat, reply)
    tcs = team_chat_session(sat)
    return unless tcs

    tcs.team_chat_messages.create!(
      sender_type: "agent",
      sender_id: sat.child_agent.id,
      content: reply.truncate(4000),
      metadata: { sub_agent: true, task_key: sat.task_key, parent_agent: sat.parent_agent.name }
    )
  rescue StandardError => e
    Rails.logger.warn("[SubAgent] Failed to persist team chat message: #{e.message}")
  end
end
