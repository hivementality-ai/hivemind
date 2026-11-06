# frozen_string_literal: true

require "rails_helper"

RSpec.describe "db/seeds/agent_templates.rb" do
  let(:seed_file) { Rails.root.join("db/seeds/agent_templates.rb") }

  def run_seed
    original = $stdout
    $stdout = StringIO.new
    load seed_file
  ensure
    $stdout = original
  end

  it "moves an existing template row off the old model ids" do
    run_seed
    template = AgentTemplate.find_by!(name: "Software Engineer")
    template.update!(model_config: template.model_config.merge("model" => "claude-sonnet-4-5"))

    run_seed

    expect(template.reload.model_config["model"]).to eq(LlmModelRegistry::Anthropic::SONNET_5_5)
  end

  it "seeds every template on the newest Sonnet or Haiku" do
    run_seed

    models = AgentTemplate.all.map { |t| t.model_config["model"] }.uniq
    expect(models).to contain_exactly(LlmModelRegistry::Anthropic::SONNET_5_5, LlmModelRegistry::Anthropic::HAIKU_5_5)
  end

  it "leaves existing agents on the model their owner picked" do
    agent = create(:agent, model_provider: "anthropic", llm_model: "claude-sonnet-4-5")

    run_seed

    expect(agent.reload.llm_model).to eq("claude-sonnet-4-5")
  end
end
