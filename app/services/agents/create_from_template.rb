# frozen_string_literal: true

module Agents
  # Create an agent from a template
  class CreateFromTemplate
    def self.call(template:, name: nil, team: nil)
      new(template: template, name: name, team: team).call
    end

    def initialize(template:, name: nil, team: nil)
      @template = template
      @name = name || template.name
      @team = team
    end

    def call
      agent = Agent.new(
        name: @name,
        role: @template.role,
        team: @team,
        model_config: @template.model_config,
        tools_config: @template.tools_config,
        system_prompt: @template.system_prompt
      )

      if agent.save
        setup_workspace(agent)

        Audit::Log.call(
          actor: "system",
          action: "agent.created_from_template",
          resource: agent,
          metadata: { template_id: @template.id, template_name: @template.name }
        )

        ServiceResponse.success(data: { agent: agent })
      else
        ServiceResponse.failure(error: agent.errors.full_messages.join(", "))
      end
    rescue => e
      ServiceResponse.failure(error: "Failed to create agent from template: #{e.message}")
    end

    private

    def setup_workspace(agent)
      # Create workspace directory
      workspace_path = Rails.root.join("storage", "workspaces", agent.id.to_s)
      FileUtils.mkdir_p(workspace_path)

      # Write SOUL.md if template has it
      if @template.soul_md.present?
        File.write(workspace_path.join("SOUL.md"), @template.soul_md)
      end

      # Create memory directory
      FileUtils.mkdir_p(workspace_path.join("memory"))

      # Update agent with workspace path
      agent.update(workspace_path: workspace_path.to_s)
    end
  end
end
