# frozen_string_literal: true

module OpenClaw
  class IdentityParser
    def self.call(workspace_path:, agent_slug: nil)
      new(workspace_path:, agent_slug:).call
    end

    def initialize(workspace_path:, agent_slug: nil)
      @workspace_path = workspace_path
      @agent_slug = agent_slug
    end

    def call
      identity = parse_identity
      agent_name = identity[:name] || "Imported Agent"

      slug = @agent_slug || agent_name.parameterize(separator: "_")
      existing = Agent.find_by(slug: slug)

      if existing
        apply_soul(existing)
        return ServiceResponse.success(data: { agent: existing, created: false })
      end

      agent = Agent.create!(
        name: agent_name,
        slug: slug,
        llm_model: LlmModelRegistry::Anthropic::DEFAULT_MID,
        model_provider: "anthropic",
        enabled: true,
        role: "General Assistant",
        team_id: Team.first&.id || Team.create!(name: "Default").id
      )

      apply_soul(agent)
      ServiceResponse.success(data: { agent: agent, created: true })
    rescue StandardError => e
      ServiceResponse.failure(error: "Identity import failed: #{e.message}")
    end

    private

    def parse_identity
      identity_path = File.join(@workspace_path, "IDENTITY.md")
      return {} unless File.exist?(identity_path)

      content = File.read(identity_path)
      name = content.match(/\*\*Name:\*\*\s*(.+)/)&.captures&.first&.strip
      emoji = content.match(/\*\*Emoji:\*\*\s*(.+)/)&.captures&.first&.strip
      vibe = content.match(/\*\*Vibe:\*\*\s*(.+)/)&.captures&.first&.strip

      { name: name, emoji: emoji, vibe: vibe }
    end

    def apply_soul(agent)
      soul_path = File.join(@workspace_path, "SOUL.md")
      return unless File.exist?(soul_path)

      soul_content = File.read(soul_path).strip
      return if soul_content.blank?

      if agent.custom_instructions.blank?
        agent.update!(custom_instructions: soul_content)
      end
    end
  end
end
