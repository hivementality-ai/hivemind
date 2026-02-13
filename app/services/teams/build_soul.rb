# frozen_string_literal: true

module Teams
  # Generates internal team context from the team description and its agents.
  # This is appended to each agent's system prompt during team chat —
  # never shown in the UI.
  class BuildSoul
    def self.call(team:)
      new(team:).call
    end

    def initialize(team:)
      @team = team
    end

    def call
      parts = []
      parts << "# Team: #{@team.name}"
      parts << ""
      parts << @team.description.to_s if @team.description.present?
      parts << ""
      parts << "## Team Members"
      parts << ""

      agents = @team.agents.order(:name)
      if agents.any?
        agents.each do |agent|
          parts << "### #{agent.name} — #{agent.role}"
          if agent.full_system_prompt.present?
            summary = agent.full_system_prompt.truncate(300, omission: "…")
            parts << summary
          end
          parts << ""
        end
      else
        parts << "_No team members yet._"
        parts << ""
      end

      soul = parts.join("\n").strip
      @team.update!(soul: soul)
      soul
    end
  end
end
