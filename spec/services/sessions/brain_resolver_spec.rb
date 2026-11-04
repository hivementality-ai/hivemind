# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::BrainResolver do
  let(:agent_config) { create(:provider_config, :openai) }
  let(:project_config) { create(:provider_config, :anthropic) }
  let(:session_config) { create(:provider_config, :ollama) }
  let(:agent) { create(:agent, provider_config: agent_config, model_provider: "openai", llm_model: "gpt-agent") }
  let(:project) { create(:project, provider_config: project_config, llm_model: "claude-project") }
  let(:session) { create(:session, agent: agent) }

  subject(:brain) { described_class.call(session:, agent:) }

  it "uses the agent when nothing is overridden" do
    expect(brain.model).to eq("gpt-agent")
    expect(brain.provider_name).to eq("openai")
    expect(brain.provider_config).to eq(agent_config)
  end

  it "uses the project override over the agent" do
    session.update!(project:)

    expect(brain.model).to eq("claude-project")
    expect(brain.provider_name).to eq("anthropic")
    expect(brain.provider_config).to eq(project_config)
  end

  it "finds the project through a task attached to the session" do
    create(:task, project:, session:)

    expect(brain.model).to eq("claude-project")
  end

  it "uses the session override over the project and agent" do
    session.update!(project:, provider_config: session_config, llm_model: "llama-session")

    expect(brain.model).to eq("llama-session")
    expect(brain.provider_name).to eq("ollama")
    expect(brain.provider_config).to eq(session_config)
  end

  it "keeps the agent's provider when an override names only a model" do
    session.update!(llm_model: "gpt-session")

    expect(brain.model).to eq("gpt-session")
    expect(brain.provider_config).to eq(agent_config)
  end

  it "passes the auto model through untouched" do
    session.update!(provider_config: agent_config, llm_model: "auto")

    expect(brain.model).to eq("auto")
  end

  it "ignores an override with no model" do
    session.update!(provider_config: session_config)

    expect(brain.model).to eq("gpt-agent")
    expect(brain.provider_config).to eq(agent_config)
  end
end
