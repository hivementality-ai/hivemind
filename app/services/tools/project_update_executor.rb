# frozen_string_literal: true

module Tools
  class ProjectUpdateExecutor < BaseExecutor
    def call
      milestone_id = input["milestone_id"]
      new_status = input["status"]
      notes = input["notes"]
      deliverables = input["deliverables"] || []
      blocker = input["blocker"]
      completed_steps = input["completed_steps"] || []
      pending_steps = input["pending_steps"] || []

      milestone = ProjectMilestone.find_by(id: milestone_id)
      return ServiceResponse.failure(error: "Milestone not found") unless milestone

      valid_statuses = %w[in_progress needs_review blocked]
      return ServiceResponse.failure(error: "Invalid status: #{new_status}") unless valid_statuses.include?(new_status)

      updates = { status: new_status }
      updates[:agent_notes] = notes if notes.present?
      updates[:deliverables] = milestone.deliverables + deliverables if deliverables.any?

      # Save checkpoint data
      if completed_steps.any? || pending_steps.any?
        Projects::CheckpointWriter.call(
          milestone: milestone,
          agent: @agent,
          session: @session,
          completed_steps: completed_steps,
          pending_steps: pending_steps,
          notes: notes
        )
      end

      case new_status
      when "needs_review"
        if milestone.auto_approve?
          updates[:status] = "completed"
          updates[:completed_at] = Time.current
          event_type = "milestone_completed"
          summary = "Milestone auto-approved and completed: #{milestone.title}"
        else
          event_type = "needs_review"
          summary = "Milestone ready for review: #{milestone.title}"
        end
      when "blocked"
        event_type = "blocked"
        summary = "Milestone blocked: #{milestone.title}. Reason: #{blocker}"
        updates[:metadata] = milestone.metadata.merge("blocker" => blocker)
      when "in_progress"
        event_type = "milestone_started"
        summary = "Agent resumed work on: #{milestone.title}"
      end

      milestone.update!(updates)

      Projects::EventLogger.call(
        project: milestone.project,
        milestone: milestone,
        agent: @agent,
        event_type: event_type,
        summary: summary
      )

      # Notify if needs review
      if new_status == "needs_review" && !milestone.auto_approve?
        Projects::NotificationDispatcher.call(
          project: milestone.project,
          milestone: milestone,
          message: "Milestone \"#{milestone.title}\" is ready for your review. Reply #approve or #deny.",
          notification_type: "needs_review"
        )
      end

      # Store project memory
      if new_status.in?(%w[needs_review completed])
        store_project_memory(milestone, notes)
      end

      ServiceResponse.success(data: {
        output: "Milestone \"#{milestone.title}\" updated to #{milestone.status}. #{notes}"
      })
    end

    private

    def store_project_memory(milestone, notes)
      return unless @agent

      MemoryEntry.create(
        agent: @agent,
        content: "[Project: #{milestone.project.title}] Completed milestone: #{milestone.title}. #{notes}",
        memory_type: "episodic",
        importance: 0.7,
        metadata: { project_id: milestone.project_id, milestone_id: milestone.id }
      )
    rescue StandardError => e
      Rails.logger.warn("[ProjectUpdateExecutor] Memory save failed: #{e.message}")
    end
  end
end
