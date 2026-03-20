# frozen_string_literal: true

module Projects
  class MilestonePlanner
    def self.call(project:, goal: nil)
      new(project: project, goal: goal).call
    end

    def initialize(project:, goal: nil)
      @project = project
      @goal = goal || project.description
    end

    def call
      agent = find_planning_agent
      return [] unless agent

      result = Agents::PlanGenerator.call(agent: agent, task: @goal)
      return [] unless result.success?

      plan = result.data[:plan]
      create_milestones_from_plan(plan)
    end

    private

    def find_planning_agent
      @project.lead_agent || @project.team.agents.enabled.first
    end

    def create_milestones_from_plan(plan)
      phases = plan["phases"] || []
      milestones = []
      previous_id = nil

      phases.each_with_index do |phase, idx|
        milestone = @project.milestones.create!(
          title: phase["name"],
          description: (phase["objectives"] || []).join("; "),
          acceptance_criteria: phase["expected_output"],
          position: idx,
          depends_on: previous_id ? [ previous_id ] : [],
          requires_approval: suggest_approval(phase, idx, phases.size),
          agent: suggest_agent(phase),
          metadata: {
            tools_needed: phase["tools_needed"],
            approach: phase["approach"]
          }
        )
        milestones << milestone
        previous_id = milestone.id
      end

      milestones
    end

    def suggest_approval(phase, index, total)
      # First and last milestones always require approval
      return true if index.zero? || index == total - 1

      # Research/gathering phases can be auto-approved
      name = phase["name"].to_s.downcase
      return false if name.match?(/research|gather|collect|analyze|investigate/)

      true
    end

    def suggest_agent(phase)
      tools_needed = phase["tools_needed"] || []
      team_agents = @project.team.agents.enabled

      # Try to match agent based on tools
      team_agents.find do |agent|
        agent_tools = agent.tools.pluck(:name)
        (tools_needed & agent_tools).any?
      end || @project.lead_agent || team_agents.first
    end
  end
end
