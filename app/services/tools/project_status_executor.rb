# frozen_string_literal: true

module Tools
  class ProjectStatusExecutor < BaseExecutor
    def call
      project_id = input["project_id"]
      detail = input["detail"] || "summary"

      project = find_project(project_id)
      return ServiceResponse.failure(error: "Project not found") unless project

      output = if detail == "full"
                 build_full_status(project)
      else
                 build_summary(project)
      end

      ServiceResponse.success(data: { output: output })
    end

    private

    def find_project(project_id)
      if project_id.present?
        Project.find_by(id: project_id)
      elsif config[:session]&.metadata&.dig("project_id")
        Project.find_by(id: config[:session].metadata["project_id"])
      end
    end

    def build_summary(project)
      lines = []
      lines << "Project: #{project.title} [#{project.status}] — #{project.progress_percentage}% complete"
      lines << "Priority: #{project.priority}"
      lines << "Deadline: #{project.deadline&.strftime('%Y-%m-%d') || 'none'}"
      lines << ""
      lines << "Milestones:"
      project.milestones.ordered.each do |m|
        agent_name = m.agent&.name || "unassigned"
        lines << "  #{m.position + 1}. #{m.title} [#{m.status}] — #{agent_name}"
      end
      lines.join("\n")
    end

    def build_full_status(project)
      lines = [ build_summary(project), "" ]

      project.milestones.ordered.each do |m|
        lines << "--- Milestone: #{m.title} ---"
        lines << "Status: #{m.status}"
        lines << "Agent: #{m.agent&.name || 'unassigned'}"
        lines << "Description: #{m.description}" if m.description.present?
        lines << "Acceptance Criteria: #{m.acceptance_criteria}" if m.acceptance_criteria.present?
        lines << "Agent Notes: #{m.agent_notes}" if m.agent_notes.present?
        lines << "Review Notes: #{m.review_notes}" if m.review_notes.present?
        lines << "Retry Count: #{m.retry_count}/#{m.max_retries}" if m.retry_count > 0
        lines << ""
      end

      recent_events = project.events.recent.limit(10)
      if recent_events.any?
        lines << "Recent Events:"
        recent_events.each do |e|
          lines << "  [#{e.created_at.strftime('%m/%d %H:%M')}] #{e.event_type}: #{e.summary}"
        end
      end

      lines.join("\n")
    end
  end
end
