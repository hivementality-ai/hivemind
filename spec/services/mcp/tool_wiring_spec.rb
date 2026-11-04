# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP tools in the agent tool list" do
  let(:agent) { create(:agent, llm_model: "gpt-4o-mini", model_provider: "openai") }
  let(:session) { create(:session, agent: agent, session_key: "mcp-#{SecureRandom.hex(4)}") }
  let(:enabled_server) { create(:mcp_server, :sse, :connected, :with_tools, name: "Docs Server") }
  let(:disabled_server) { create(:mcp_server, :sse, :connected, :with_tools, :disabled, name: "Off Server") }

  before do
    create(:agent_mcp_server, agent: agent, mcp_server: enabled_server)
    create(:agent_mcp_server, agent: agent, mcp_server: disabled_server)
  end

  describe Mcp::ToolResolver do
    it "wraps resolved tools as proxies that expose the LLM tool shape" do
      proxy = described_class.proxies(agent).find { |t| t.name == "mcp_docs_server_read_file" }

      expect(proxy.to_llm_tool).to include(name: "mcp_docs_server_read_file", description: "Read a file")
      expect(proxy.to_llm_tool[:input_schema]["properties"]).to have_key("path")
      expect(proxy.effective_config).to eq(server_id: enabled_server.id, tool_name: "read_file")
    end
  end

  describe Sessions::Chat do
    it "offers an enabled server's tools and not a disabled server's" do
      names = described_class.new(session: session, message: "hi").send(:resolve_tools, agent).map(&:name)

      expect(names).to include("mcp_docs_server_read_file", "mcp_docs_server_list_files")
      expect(names.grep(/off_server/)).to be_empty
    end
  end

  describe TeamChatJob do
    it "offers an enabled server's tools and not a disabled server's" do
      team = create(:team)
      job = described_class.new
      job.instance_variable_set(:@team, team)
      names = job.send(:resolve_tools, agent).map(&:name)

      expect(names).to include("mcp_docs_server_read_file")
      expect(names.grep(/off_server/)).to be_empty
    end
  end

  describe "executing a call" do
    it "routes through Tools::Executor to the MCP client with the original tool name" do
      proxy = Mcp::ToolResolver.proxies(agent).find { |t| t.name == "mcp_docs_server_read_file" }
      allow(Mcp::HttpClient).to receive(:call_tool)
        .and_return(ServiceResponse.success(data: { output: "file body" }))

      result = Tools::Executor.call(tool: proxy, input: { "path" => "/a" }, agent: agent, session: session)

      expect(result).to be_success
      expect(result.data[:output]).to eq("file body")
      expect(Mcp::HttpClient).to have_received(:call_tool)
        .with(enabled_server, tool_name: "read_file", arguments: { "path" => "/a" })
    end

    it "does not let model input redirect the call to another server" do
      proxy = Mcp::ToolResolver.proxies(agent).find { |t| t.name == "mcp_docs_server_read_file" }
      allow(Mcp::HttpClient).to receive(:call_tool)
        .and_return(ServiceResponse.success(data: { output: "ok" }))

      Tools::Executor.call(tool: proxy, input: { "server_id" => disabled_server.id, "tool_name" => "x" }, agent: agent, session: session)

      expect(Mcp::HttpClient).to have_received(:call_tool).with(enabled_server, hash_including(tool_name: "read_file"))
    end
  end
end
