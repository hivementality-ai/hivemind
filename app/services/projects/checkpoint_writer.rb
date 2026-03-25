# frozen_string_literal: true

module Projects
  class CheckpointWriter
    def self.call(milestone:, agent:, session:, completed_steps: [], pending_steps: [], results: {}, notes: nil)
      new(milestone: milestone, agent: agent, session: session,
          completed_steps: completed_steps, pending_steps: pending_steps,
          results: results, notes: notes).call
    end

    def initialize(milestone:, agent:, session:, completed_steps: [], pending_steps: [], results: {}, notes: nil)
      @milestone = milestone
      @agent = agent
      @session = session
      @completed_steps = completed_steps
      @pending_steps = pending_steps
      @results = results
      @notes = notes
    end

    def call
      checkpoint = {
        "last_updated" => Time.current.iso8601,
        "completed_steps" => @completed_steps,
        "pending_steps" => @pending_steps,
        "intermediate_results" => @results,
        "context_notes" => @notes,
        "session_id" => @session.id,
        "tool_calls_made" => count_tool_calls
      }

      @milestone.update!(checkpoint: checkpoint)

      Projects::EventLogger.call(
        project: @milestone.project,
        milestone: @milestone,
        agent: @agent,
        event_type: "checkpoint_saved",
        summary: "Progress checkpoint: #{@completed_steps.size} steps done, #{@pending_steps.size} remaining"
      )
    end

    private

    def count_tool_calls
      @session.transcript&.count { |m| (m["role"] || m[:role]) == "tool" } || 0
    end
  end
end
