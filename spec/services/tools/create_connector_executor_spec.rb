# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CreateConnectorExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:input) do
    {
      "name" => "Widgets", "slug" => "widgets", "base_url" => "https://api.widgets.test/v1",
      "auth_scheme" => "bearer", "auth_config" => { "secret" => "vault:widgets/token" },
      "operations" => attributes_for(:connector)[:operations].map(&:stringify_keys)
    }
  end

  def run(payload)
    described_class.new(input: payload, agent: agent).call
  end

  it "creates a disabled connector" do
    result = run(input)

    expect(result).to be_success
    expect(Connector.find_by(slug: "widgets")).not_to be_enabled
  end

  it "refuses a raw secret" do
    result = run(input.merge("auth_config" => { "secret" => "sk-live-abc123" }))

    expect(result).not_to be_success
    expect(Connector.count).to eq(0)
  end

  it "is registered as an executor type" do
    expect(Tools::Executor::BUILTIN_EXECUTORS["create_connector"]).to eq(described_class)
  end
end
