# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261104120000_add_provider_config_to_agents")

RSpec.describe AddProviderConfigToAgents do
  # Runs the backfill only; the column already exists in the test schema, and
  # altering the table here would invalidate cached plans for later specs.
  def backfill
    migration = described_class.new
    allow(migration).to receive(:add_reference)
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  it "pins existing agents to the first enabled config of their adapter type" do
    first = create(:provider_config, :openai_compatible, name: "oMLX")
    create(:provider_config, :openai_compatible, name: "OpenRouter")
    create(:provider_config, :ollama, :disabled, name: "Old Ollama")
    compat = create(:agent, model_provider: "openai_compatible")
    ollama = create(:agent, model_provider: "ollama")

    Agent.update_all(provider_config_id: nil)
    backfill

    expect(compat.reload.provider_config_id).to eq(first.id)
    expect(ollama.reload.provider_config_id).to be_nil
  end
end
