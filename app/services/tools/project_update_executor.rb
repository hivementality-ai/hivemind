# frozen_string_literal: true

module Tools
  class ProjectUpdateExecutor < BaseExecutor
    def call
      action = input["action"] || "update_milestone"

      case action
      when "update_milestone" then update_milestone
      when "update_project" then update_project
      when "add_milestone" then add_milestone
      when "remove_milestone" then remove_milestone
      when "edit_milestone" then edit_milestone
      when "assign_agent" then assign_agent
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Use: update_milestone, update_project, add_milestone, remove_milestone, edit_milestone, assign_agent")
      end
    end

    private

    # ── Original milestone status update (backwards compatible) ──

    def update_milestone
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

      session = config[:session]

      updates = { status: new_status }
      updates[:agent_notes] = notes if notes.present?
      updates[:deliverables] = (milestone.deliverables || []) + deliverables if deliverables.any?

      if (completed_steps.any? || pending_steps.any?) && session
        Projects::CheckpointWriter.call(
          milestone: milestone,
          agent: agent,
          session: session,
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
        agent: agent,
        event_type: event_type,
        summary: summary
      )

      if new_status == "needs_review" && !milestone.auto_approve?
        Projects::NotificationDispatcher.call(
          project: milestone.project,
          milestone: milestone,
          message: "Milestone \"#{milestone.title}\" is ready for your review. Reply #approve or #deny.",
          notification_type: "needs_review"
        )
      end

      store_project_memory(milestone, notes) if new_status.in?(%w[needs_review completed])

      ServiceResponse.success(data: {
        output: "Milestone \"#{milestone.title}\" updated to #{milestone.status}. #{notes}"
      })
    end

    # ── Update project details ──

    def update_project
      project = find_project
      return project unless project.is_a?(Project)

      updates = {}
      updates[:title] = input["title"] if input["title"].present?
      updates[:description] = input["description"] if input["description"].present?
      updates[:priority] = input["priority"] if input["priority"].present? && %w[low normal high urgent].include?(input["priority"])
      updates[:status] = input["project_status"] if input["project_status"].present? && %w[planning active paused].include?(input["project_status"])

      if input["lead_agent_name"].present?
        lead = Agent.enabled.find_by("LOWER(name) = ?", input["lead_agent_name"].downcase)
        updates[:lead_agent_id] = lead.id if lead
      end

      return ServiceResponse.failure(error: "No valid fields to update") if updates.empty?

      project.update!(updates)

      Projects::EventLogger.call(
        project: project,
        agent: agent,
        event_type: "project_updated",
        summary: "Project updated by #{agent&.name}: #{updates.keys.join(', ')}"
      )

      ServiceResponse.success(data: {
        output: "Project \"#{project.title}\" updated: #{updates.keys.join(', ')}"
      })
    end

    # ── Add milestone to project ──

    def add_milestone
      project = find_project
      return project unless project.is_a?(Project)

      title = input["title"]
      return ServiceResponse.failure(error: "Milestone title is required") if title.blank?

      position = project.milestones.maximum(:position).to_i + 1

      attrs = {
        title: title,
        description: input["description"],
        acceptance_criteria: input["acceptance_criteria"],
        position: position,
        requires_approval: input.fetch("requires_approval", true)
      }

      if input["agent_name"].present?
        assigned = Agent.enabled.find_by("LOWER(name) = ?", input["agent_name"].downcase)
        attrs[:agent] = assigned if assigned
      end

      milestone = project.milestones.create!(attrs)

      Projects::EventLogger.call(
        project: project,
        agent: agent,
        event_type: "milestone_added",
        summary: "Milestone added by #{agent&.name}: #{title}"
      )

      ServiceResponse.success(data: {
        output: "Milestone \"#{title}\" added to \"#{project.title}\" (ID: #{milestone.id}, position: #{position})"
      })
    end

    # ── Remove milestone ──

    def remove_milestone
      milestone = ProjectMilestone.find_by(id: input["milestone_id"])
      return ServiceResponse.failure(error: "Milestone not found") unless milestone
      return ServiceResponse.failure(error: "Cannot remove in-progress or completed milestones") if milestone.status.in?(%w[in_progress completed needs_review])

      project = milestone.project
      title = milestone.title
      milestone.destroy!

      Projects::EventLogger.call(
        project: project,
        agent: agent,
        event_type: "milestone_removed",
        summary: "Milestone removed by #{agent&.name}: #{title}"
      )

      ServiceResponse.success(data: { output: "Milestone \"#{title}\" removed from \"#{project.title}\"" })
    end

    # ── Edit milestone details ──

    def edit_milestone
      milestone = ProjectMilestone.find_by(id: input["milestone_id"])
      return ServiceResponse.failure(error: "Milestone not found") unless milestone

      updates = {}
      updates[:title] = input["title"] if input["title"].present?
      updates[:description] = input["description"] if input["description"].present?
      updates[:acceptance_criteria] = input["acceptance_criteria"] if input["acceptance_criteria"].present?
      updates[:requires_approval] = input["requires_approval"] unless input["requires_approval"].nil?

      if input["agent_name"].present?
        assigned = Agent.enabled.find_by("LOWER(name) = ?", input["agent_name"].downcase)
        updates[:agent] = assigned if assigned
      elsif input.key?("agent_name") && input["agent_name"].nil?
        updates[:agent_id] = nil
      end

      return ServiceResponse.failure(error: "No valid fields to update") if updates.empty?

      milestone.update!(updates)

      Projects::EventLogger.call(
        project: milestone.project,
        milestone: milestone,
        agent: agent,
        event_type: "milestone_edited",
        summary: "Milestone edited by #{agent&.name}: #{updates.keys.join(', ')}"
      )

      ServiceResponse.success(data: {
        output: "Milestone \"#{milestone.title}\" updated: #{updates.keys.join(', ')}"
      })
    end

    # ── Reassign agent to milestone ──

    def assign_agent
      milestone = ProjectMilestone.find_by(id: input["milestone_id"])
      return ServiceResponse.failure(error: "Milestone not found") unless milestone

      agent_name = input["agent_name"]
      if agent_name.present?
        assigned = Agent.enabled.find_by("LOWER(name) = ?", agent_name.downcase)
        return ServiceResponse.failure(error: "Agent '#{agent_name}' not found") unless assigned
        milestone.update!(agent: assigned)
        msg = "Milestone \"#{milestone.title}\" assigned to #{assigned.name}"
      else
        milestone.update!(agent_id: nil)
        msg = "Milestone \"#{milestone.title}\" unassigned"
      end

      Projects::EventLogger.call(
        project: milestone.project,
        milestone: milestone,
        agent: agent,
        event_type: "agent_assigned",
        summary: msg
      )

      ServiceResponse.success(data: { output: msg })
    end

    # ── Helpers ──

    def find_project
      if input["project_id"].present?
        project = Project.find_by(id: input["project_id"])
        return ServiceResponse.failure(error: "Project not found") unless project
        project
      elsif input["milestone_id"].present?
        milestone = ProjectMilestone.find_by(id: input["milestone_id"])
        return ServiceResponse.failure(error: "Milestone not found") unless milestone
        milestone.project
      else
        ServiceResponse.failure(error: "Provide project_id or milestone_id")
      end
    end

    def store_project_memory(milestone, notes)
      return unless agent

      MemoryEntry.create(
        agent: agent,
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
