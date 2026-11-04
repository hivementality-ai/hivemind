# frozen_string_literal: true

module Sessions
  # Picks the provider and model that answer a chat turn: the session's own
  # override, else its project's, else the agent's. An override level applies
  # once it names a model; its provider falls back to the agent's when unset.
  class BrainResolver
    Brain = Struct.new(:provider_config, :provider_name, :model, keyword_init: true)

    def self.call(session: nil, agent: nil)
      new(session:, agent:).call
    end

    def initialize(session: nil, agent: nil)
      @session = session
      @agent = agent || session&.agent
    end

    # @return [Brain]
    def call
      level = [ @session, project ].compact.find { |l| l.llm_model.present? }
      return agent_brain unless level

      config = level.provider_config || @agent.provider_config
      Brain.new(
        provider_config: config,
        provider_name: config&.adapter_type || @agent.model_provider,
        model: level.llm_model
      )
    end

    private

    def agent_brain
      Brain.new(
        provider_config: @agent.provider_config,
        provider_name: @agent.model_provider,
        model: @agent.llm_model
      )
    end

    def project
      return unless @session

      @session.project || Task.where(session_id: @session.id).where.not(project_id: nil).order(:id).last&.project
    end
  end
end
