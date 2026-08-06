# frozen_string_literal: true

module Delegations
  # The single entry point for one agent delegating a task to another.
  # Every guardrail lives behind this interface: team scoping, spawn-time
  # depth limits, per-session fan-out caps, and duplicate-task rejection.
  # Callers get back either a task_key or an actionable error string the
  # LLM can read and change course on.
  class Request
    def self.call(from_agent:, from_session:, target_name:, task:)
      new(from_agent:, from_session:, target_name:, task:).call
    end

    def initialize(from_agent:, from_session:, target_name:, task:)
      @from_agent = from_agent
      @from_session = from_session
      @target_name = target_name.to_s.strip
      @task = task.to_s.strip
    end

    def call
      return ServiceResponse.failure(error: "No agent name provided") if @target_name.empty?
      return ServiceResponse.failure(error: "No task provided") if @task.empty?

      target = find_target
      unless target
        return ServiceResponse.failure(error: "Agent '#{@target_name}' not found. Available: #{available_agent_names}")
      end

      if @from_agent && target.id == @from_agent.id
        return ServiceResponse.failure(error: "Cannot delegate to yourself — try performing the task directly")
      end

      depth = current_depth + 1
      if depth > Config.max_depth
        return ServiceResponse.failure(
          error: "Delegation depth limit reached (#{Config.max_depth}). Complete this task yourself instead of delegating further."
        )
      end

      active = active_delegations
      if active.count >= Config.max_concurrent_per_session
        return ServiceResponse.failure(
          error: "Too many active delegations (#{Config.max_concurrent_per_session} max). Wait for existing tasks to finish — check them with delegation_status."
        )
      end

      if Config.dedup_pending? && (duplicate = active.detect { |sat| sat.task == @task })
        return ServiceResponse.failure(
          error: "An identical task is already delegated to #{duplicate.child_agent.name} (Task ID: #{duplicate.task_key}). Check it with delegation_status instead of delegating again."
        )
      end

      sat = SubAgentTask.create!(
        parent_agent: @from_agent || target,
        child_agent: target,
        parent_session: @from_session,
        task: @task,
        task_key: SecureRandom.hex(8),
        status: "pending",
        depth: depth
      )

      SubAgentJob.perform_later(sat.id)

      ServiceResponse.success(data: { task_key: sat.task_key, target: target })
    rescue StandardError => e
      ServiceResponse.failure(error: "Delegation failed: #{e.message}")
    end

    private

    # Agents on a team may only delegate within their team. Teamless agents
    # keep the historical behavior of seeing all visible enabled agents.
    def delegation_pool
      scope = Agent.visible.enabled
      return scope unless @from_agent&.team_id

      scope.where(team_id: @from_agent.team_id)
    end

    def find_target
      delegation_pool.where("LOWER(name) = ?", @target_name.downcase).first
    end

    def available_agent_names
      delegation_pool.where.not(id: @from_agent&.id).pluck(:name).join(", ")
    end

    # Depth of the session doing the delegating: 0 for a normal session,
    # N for a sub-agent session spawned at depth N (stamped in metadata
    # by SubAgentJob).
    def current_depth
      @from_session&.metadata&.dig("delegation_depth").to_i
    end

    def active_delegations
      return SubAgentTask.none unless @from_session

      SubAgentTask.active.where(parent_session_id: @from_session.id).includes(:child_agent)
    end
  end
end
