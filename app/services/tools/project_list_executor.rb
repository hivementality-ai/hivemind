# frozen_string_literal: true

module Tools
  class ProjectListExecutor < BaseExecutor
    def call
      team = agent&.team
      return ServiceResponse.failure(error: "Agent must belong to a team") unless team

      status_filter = input["status"]
      projects = Project.for_team(team).visible.order(updated_at: :desc)
      projects = projects.where(status: status_filter) if status_filter.present?

      return ServiceResponse.failure(error: "No projects found for your team. Use project_create to start one.") if projects.empty?

      lines = [ "Found #{projects.size} project(s):", "" ]
      projects.each do |p|
        lines << "  [ID:#{p.id}] #{p.title} [#{p.status}] — #{p.progress_percentage}% complete"
      end
      lines << ""
      lines << "Use project_status with a project_id for full details."

      ServiceResponse.success(data: { output: lines.join("\n") })
    end
  end
end
