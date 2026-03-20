# frozen_string_literal: true

module Tools
  class ProjectCreateExecutor < BaseExecutor
    def call
      title = input["title"]
      description = input["description"]
      milestones_data = input["milestones"] || []
      priority = input["priority"] || "normal"

      return ServiceResponse.failure(error: "Title is required") if title.blank?

      team = @agent&.team
      return ServiceResponse.failure(error: "Agent must belong to a team") unless team

      # Find a user to own the project (session starter or first admin)
      owner = find_owner

      project = Project.create!(
        team: team,
        user: owner,
        title: title,
        description: description,
        priority: priority,
        status: "planning"
      )

      # Create milestones from agent's proposal
      milestones_data.each_with_index do |m_data, idx|
        project.milestones.create!(
          title: m_data["title"],
          description: m_data["description"],
          acceptance_criteria: m_data["acceptance_criteria"],
          position: idx,
          depends_on: m_data["depends_on"] || [],
          requires_approval: m_data.fetch("requires_approval", true),
          agent: resolve_agent(m_data["agent_name"])
        )
      end

      Projects::EventLogger.call(
        project: project,
        agent: @agent,
        event_type: "project_created",
        summary: "Project proposed by #{@agent&.name}: #{title} (#{milestones_data.size} milestones)"
      )

      ServiceResponse.success(data: {
        output: "Project \"#{title}\" created with #{milestones_data.size} milestones. " \
                "Awaiting user approval to start. Project ID: #{project.id}"
      })
    end

    private

    def find_owner
      user_id = @session&.metadata&.dig("started_by")
      User.find_by(id: user_id) || User.where(role: [ :admin, :owner ]).first
    end

    def resolve_agent(agent_name)
      return nil if agent_name.blank?

      Agent.enabled.find_by("LOWER(name) = ?", agent_name.downcase)
    end
  end
end
