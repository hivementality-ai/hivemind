# frozen_string_literal: true

class SubAgentJob < ApplicationJob
  queue_as :default

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
        parent_agent: sat.parent_agent.name
      }
    )

    sat.update!(child_session: session)

    # Run the task through the agent's full pipeline (tools, memory, everything)
    result = Sessions::Chat.call(
      session: session,
      message: sat.task,
      agent: agent
    )

    if result.success?
      reply = result.data[:reply].to_s
      sat.update!(
        status: "completed",
        result: reply,
        completed_at: Time.current
      )

      # Notify parent via ActionCable
      notify_parent(sat, reply)
    else
      sat.update!(
        status: "failed",
        result: "Error: #{result.error}",
        completed_at: Time.current
      )
      notify_parent(sat, "Sub-agent failed: #{result.error}")
    end
  rescue StandardError => e
    sat&.update!(status: "failed", result: "Error: #{e.message}", completed_at: Time.current)
    Rails.logger.error("[SubAgent] Task #{sub_agent_task_id} failed: #{e.message}")
  end

  private

  def notify_parent(sat, reply)
    return unless sat.parent_session

    # Broadcast to parent's session
    ActionCable.server.broadcast(
      "session_#{sat.parent_session.session_key}",
      {
        type: "sub_agent_complete",
        task_key: sat.task_key,
        child_agent: sat.child_agent.name,
        task: sat.task.truncate(100),
        result: reply.truncate(2000),
        duration: sat.duration_seconds,
        timestamp: Time.current.iso8601
      }
    )
  end
end
