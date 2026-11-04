# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connectors::ToolResolver do
  let(:agent) { create(:agent, llm_model: "gpt-4o-mini", model_provider: "openai") }

  describe ".proxies" do
    it "exposes each operation of an enabled connector as connector__slug__op" do
      create(:connector, slug: "widgets")

      names = described_class.proxies(agent).map(&:name)

      expect(names).to contain_exactly("connector__widgets__get_widget", "connector__widgets__create_widget")
    end

    it "skips disabled connectors" do
      create(:connector, slug: "off", enabled: false)

      expect(described_class.proxies(agent)).to be_empty
    end

    it "shapes the LLM tool from the operation and carries the call target" do
      connector = create(:connector, slug: "widgets")

      proxy = described_class.proxies(agent).find { |t| t.name == "connector__widgets__get_widget" }

      expect(proxy.to_llm_tool).to include(name: "connector__widgets__get_widget", description: "Fetch one widget")
      expect(proxy.to_llm_tool[:input_schema]["required"]).to eq([ "id" ])
      expect(proxy.effective_config).to eq(connector_id: connector.id, operation: "get_widget")
      expect(proxy.executor_type).to eq("connector")
    end

    it "keeps long names within the model limit and unique" do
      long = "a" * 40
      create(:connector, slug: long, operations: [ "b", "c" ].map do |suffix|
        { "name" => "#{suffix * 39}", "description" => "d", "method" => "GET", "path" => "/x", "read_only" => true }
      end)

      names = described_class.proxies(agent).map(&:name)

      expect(names.map(&:length).max).to be <= 64
      expect(names.uniq.size).to eq(2)
      expect(names).to all(match(/\A[a-zA-Z0-9_-]{1,64}\z/))
    end
  end

  describe "in the agent tool list" do
    let(:session) { create(:session, agent: agent, session_key: "conn-#{SecureRandom.hex(4)}") }

    it "is offered to the agent in a chat session" do
      create(:connector, slug: "widgets")

      names = Sessions::Chat.new(session: session, message: "hi").send(:resolve_tools, agent).map(&:name)

      expect(names).to include("connector__widgets__get_widget")
    end
  end

  describe "running a connector tool" do
    it "goes through Tools::Executor to the connector" do
      create(:connector, slug: "widgets")
      allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "93.184.216.34" ])
      stub_request(:get, "https://api.widgets.test/v1/widgets/7").to_return(status: 200, body: '{"id":7}')
      proxy = described_class.proxies(agent).find { |t| t.name == "connector__widgets__get_widget" }

      result = Tools::Executor.call(tool: proxy, input: { "id" => "7" }, agent: agent, session: create(:session, agent: agent))

      expect(result).to be_success
      expect(result.data[:output]).to eq('{"id":7}')
    end
  end
end
