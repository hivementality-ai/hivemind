# frozen_string_literal: true

module TeamChats
  # Marks an agent as working while it runs a team chat turn, so the chat
  # header, sidebar and working chip show it instead of a permanent "idle".
  # The status lives on Agent#status and is announced on the team chat channel.
  module AgentActivity
    HEARTBEAT_INTERVAL = 30
    # A busy status older than this belongs to a worker that died mid-turn.
    STALE_AFTER = 3 * HEARTBEAT_INTERVAL

    WORKING_STATUSES = %w[thinking executing].freeze

    module_function

    # Runs the block with +agent+ marked as thinking, touching the record while
    # it runs and resetting it to idle however the block ends.
    #
    # @param agent [Agent]
    # @param channel [String] team chat ActionCable channel
    # @param task [String] label shown next to the status
    def track(agent, channel:, task: "Responding in team chat")
      stop = Thread::Queue.new
      heartbeat = nil
      mark(agent, channel, :thinking, task)
      heartbeat = start_heartbeat(agent, stop)
      yield
    ensure
      stop << true
      heartbeat&.join
      mark(agent, channel, :idle, nil)
    end

    # @return [Boolean] true while the agent has a fresh thinking/executing status
    def working?(agent)
      WORKING_STATUSES.include?(agent.status) && agent.updated_at > STALE_AFTER.seconds.ago
    end

    def mark(agent, channel, status, task)
      agent.update_columns(status: Agent.statuses.fetch(status.to_s), current_task: task, updated_at: Time.current)
      ActionCable.server.broadcast(channel, {
        type: "agent_status", agent_id: agent.id, agent_name: agent.name, status: status.to_s, current_task: task
      })
    rescue StandardError => e
      Rails.logger.warn("[TeamChats::AgentActivity] #{status} for agent #{agent.id} failed: #{e.message}")
    end

    def start_heartbeat(agent, stop)
      Thread.new do
        until stop.pop(timeout: HEARTBEAT_INTERVAL)
          ActiveRecord::Base.connection_pool.with_connection { Agent.where(id: agent.id).update_all(updated_at: Time.current) }
        end
      rescue StandardError => e
        Rails.logger.warn("[TeamChats::AgentActivity] heartbeat stopped: #{e.message}")
      end
    end
  end
end
