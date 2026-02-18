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

    DEFAULT_VIBE = <<~VIBE.strip
      ## Team Vibe
      You're part of a small, tight team. Act like it.
      - Keep it casual. Talk like coworkers who actually like each other.
      - Don't over-explain or list out plans unless someone asks.
      - If someone's got it handled, let them handle it. Don't pile on.
      - Disagree when you disagree. "Sounds good" when you have concerns helps nobody.
      - Celebrate wins. A simple "nice" or 🔥 goes a long way.
      - When there's real work, do it. When it's just vibes, match the vibes.
    VIBE

    def call
      parts = []
      parts << "# Team: #{@team.name}"
      parts << ""
      parts << @team.description.to_s if @team.description.present?
      parts << ""

      # Custom soul from user takes priority, otherwise use default vibe
      if @team.custom_soul.present?
        parts << @team.custom_soul
      else
        parts << DEFAULT_VIBE
      end

      parts << ""
      parts << "## Team Members"
      parts << ""

      agents = @team.agents.order(:name)
      if agents.any?
        agents.each do |agent|
          parts << "### #{agent.name} — #{agent.role}"
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
