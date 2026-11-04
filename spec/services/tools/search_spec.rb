# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tool search" do
  let(:agent) { create(:agent, llm_model: "gpt-4o-mini", model_provider: "openai") }
  let(:session) { create(:session, agent: agent, session_key: "ts-#{SecureRandom.hex(4)}") }

  def op(name, description)
    { "name" => name, "description" => description, "method" => "GET", "path" => "/#{name}", "read_only" => true }
  end

  describe Tools::Search do
    let!(:billing) do
      create(:connector, name: "Stripe Billing", slug: "billing", operations: [
               op("list_invoices", "List invoices for a customer"), op("refund_charge", "Refund a charge")
             ])
    end
    let!(:crm) do
      create(:connector, name: "Acme CRM", slug: "crm", operations: [
               op("find_contact", "Look up a contact by email"), op("create_deal", "Open a new deal")
             ])
    end

    describe ".offered" do
      it "lists every connector tool when the count is at the threshold" do
        Setting.set(described_class::THRESHOLD_KEY, "4")

        expect(described_class.offered(agent).map(&:name)).to include("connector__billing__list_invoices", "connector__crm__find_contact")
        expect(described_class.offered(agent).size).to eq(4)
      end

      it "offers only find_tools and use_tool when the count is over the threshold" do
        Setting.set(described_class::THRESHOLD_KEY, "3")

        expect(described_class.offered(agent).map(&:name)).to eq(%w[find_tools use_tool])
      end

      it "defaults the threshold to 20" do
        expect(described_class.threshold).to eq(20)
        Setting.set(described_class::THRESHOLD_KEY, "nonsense")
        expect(described_class.threshold).to eq(20)
      end
    end

    describe ".rank" do
      let(:pool) { described_class.pool(agent) }

      it "ranks name and connector matches above description-only matches" do
        names = described_class.rank(pool, "refund").map(&:name)

        expect(names.first).to eq("connector__billing__refund_charge")
        expect(described_class.rank(pool, "stripe").map(&:name)).to eq(
          %w[connector__billing__list_invoices connector__billing__refund_charge]
        )
        expect(described_class.rank(pool, "email").map(&:name)).to eq([ "connector__crm__find_contact" ])
      end

      it "drops non-matches and honours the limit" do
        expect(described_class.rank(pool, "zzzz")).to be_empty
        expect(described_class.rank(pool, "connector", limit: 2).size).to eq(2)
      end
    end

    describe "meta tools in the agent tool lists" do
      before { Setting.set(described_class::THRESHOLD_KEY, "1") }

      it "gates Sessions::Chat" do
        tools = Sessions::Chat.new(session: session, message: "hi").send(:resolve_tools, agent).map(&:name)

        expect(tools).to include("find_tools", "use_tool")
        expect(tools.grep(/\Aconnector__/)).to be_empty
      end

      it "gates ChatStreamJob and keeps built-in tools" do
        builtin = create(:tool, :builtin, name: "shell_probe")
        tools = ChatStreamJob.new.send(:resolve_tools, agent).map(&:name)

        expect(tools).to include("find_tools", "use_tool", builtin.name)
        expect(tools.grep(/\Aconnector__/)).to be_empty
      end
    end

    describe Tools::FindToolsExecutor do
      it "returns name, one-line description and input schema for the best matches" do
        result = described_class.new(input: { "query" => "refund charge" }, agent: agent).call

        found = JSON.parse(result.data[:output])
        expect(found.first).to include("name" => "connector__billing__refund_charge", "description" => "Refund a charge")
        expect(found.first).to have_key("input_schema")
      end

      it "says so when nothing matches" do
        result = described_class.new(input: { "query" => "zzzz" }, agent: agent).call

        expect(result.data[:output]).to include("No tools match")
      end
    end

    describe Tools::UseToolExecutor do
      before { allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "93.184.216.34" ]) }

      it "runs through Tools::Executor with the same tool and input as a direct call" do
        direct = Connectors::ToolResolver.proxies(agent).find { |t| t.name == "connector__crm__find_contact" }
        stub_request(:get, "https://api.widgets.test/v1/find_contact?email=a%40b.c").to_return(status: 200, body: '{"id":1}')

        expected = Tools::Executor.call(tool: direct, input: { "email" => "a@b.c" }, agent: agent, session: session)
        expect(Tools::Executor).to receive(:call).with(
          hash_including(tool: have_attributes(name: direct.name, effective_config: direct.effective_config),
                         input: { "email" => "a@b.c" }, agent: agent, session: session)
        ).and_call_original

        result = described_class.new(
          input: { "name" => direct.name, "arguments" => { "email" => "a@b.c" } }, config: { session: session }, agent: agent
        ).call

        expect(result).to be_success
        expect(result.data[:output]).to eq(expected.data[:output])
      end

      it "returns the executor's failure unchanged" do
        failure = ServiceResponse.failure(error: "Egress blocked: nope")
        allow(Tools::Executor).to receive(:call).and_return(failure)

        result = described_class.new(input: { "name" => "connector__crm__find_contact" }, config: { session: session }, agent: agent).call

        expect(result).to eq(failure)
      end

      it "lists close matches for an unknown name" do
        result = described_class.new(input: { "name" => "connector__crm__find_contacts" }, agent: agent).call

        expect(result).not_to be_success
        expect(result.error).to include("Unknown tool 'connector__crm__find_contacts'", "connector__crm__find_contact")
      end

      it "points at find_tools when nothing is close" do
        result = described_class.new(input: { "name" => "zzzz" }, agent: agent).call

        expect(result.error).to include("find_tools")
      end
    end
  end

  describe "sdk-proxy execute endpoint", type: :request do
    it "resolves find_tools and use_tool as system tools" do
      create(:connector, slug: "crm", operations: [ op("find_contact", "Look up a contact") ])
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return("s3cret")

      post "/internal/tools/execute",
           params: { tool_name: "find_tools", input: { query: "contact" }, agent_id: agent.id, session_id: session.id },
           headers: { "Authorization" => "Bearer s3cret" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.parsed_body["output"]).first["name"]).to eq("connector__crm__find_contact")
    end
  end

  describe Agents::DynamicToolSchema do
    it "never drops the meta tools" do
      tools = %w[find_tools use_tool git_commit b_two c_three d_four e_five].map { |n| { name: n, description: (n == "git_commit" ? "git commit" : "x") } }

      kept = described_class.filter(tools, context: :git, discovered_names: []).map { |t| t[:name] }

      expect(kept).to contain_exactly("find_tools", "use_tool", "git_commit")
    end
  end
end
