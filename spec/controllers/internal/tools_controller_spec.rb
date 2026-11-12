# frozen_string_literal: true

require "rails_helper"

RSpec.describe Internal::ToolsController, type: :controller do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:internal_secret) { "test-internal-secret" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_secret)
    allow(ActionCable.server).to receive(:broadcast)
    request.headers["Authorization"] = "Bearer #{internal_secret}"
  end

  describe "POST #execute" do
    it "resolves teammate calls through the SDK callback endpoint" do
      allow(Tools::Executor).to receive(:call).and_return(ServiceResponse.success(data: { output: "Reviewed" }))
      post :execute, params: { tool_name: "talk_to_teammate", agent_id: agent.id, session_id: session.id, input: { teammate: "Reviewer", message: "Review" } }
      expect(response).to have_http_status(:ok)
      expect(Tools::Executor).to have_received(:call).with(tool: SystemTool::TALK_TO_TEAMMATE, agent: agent, session: session, input: { "teammate" => "Reviewer", "message" => "Review" })
    end

    it "rejects an agent using another agent's session" do
      allow(Tools::Executor).to receive(:call)
      foreign = create(:session)
      post :execute, params: { tool_name: "talk_to_teammate", agent_id: agent.id, session_id: foreign.id, input: {} }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Tools::Executor).not_to have_received(:call)
    end

    context "with a regular DB tool" do
      let(:tool) { create(:tool, enabled: true) }

      it "executes the tool and returns success" do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.success(data: { output: "Tool output" })
        )

        post :execute, params: { tool_name: tool.name, agent_id: agent.id, session_id: session.id, input: { key: "value" } }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["success"]).to be true
        expect(JSON.parse(response.body)["output"]).to eq("Tool output")
      end

      it "does not broadcast tool events (handled by SDK proxy SSE pipeline)" do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.success(data: { output: "done" })
        )

        post :execute, params: { tool_name: tool.name, agent_id: agent.id, session_id: session.id, input: {} }

        expect(ActionCable.server).not_to have_received(:broadcast)
      end

      it "returns 422 on executor failure" do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.failure(error: "Execution failed")
        )

        post :execute, params: { tool_name: tool.name, agent_id: agent.id, session_id: session.id, input: {} }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to eq("Execution failed")
      end
    end

    context "with an MCP tool of the agent" do
      let(:server) { create(:mcp_server, :sse, :connected, :with_tools, name: "Docs Server") }

      before { create(:agent_mcp_server, agent: agent, mcp_server: server) }

      it "resolves it by name and runs it" do
        allow(Mcp::HttpClient).to receive(:call_tool)
          .and_return(ServiceResponse.success(data: { output: "file body" }))

        post :execute, params: { tool_name: "mcp_docs_server_read_file", agent_id: agent.id, session_id: session.id, input: { path: "/a" } }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["output"]).to eq("file body")
      end

      it "rejects an MCP tool the agent does not have" do
        other = create(:agent)

        post :execute, params: { tool_name: "mcp_docs_server_read_file", agent_id: other.id, session_id: session.id, input: {} }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a connector operation" do
      before do
        create(:connector, slug: "widgets")
        allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "93.184.216.34" ])
        stub_request(:get, "https://api.widgets.test/v1/widgets/5").to_return(status: 200, body: "widget five")
      end

      it "resolves it by name and runs it" do
        post :execute, params: { tool_name: "connector__widgets__get_widget", agent_id: agent.id, session_id: session.id, input: { id: "5" } }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["output"]).to eq("widget five")
      end
    end

    context "with a system tool (load_skill)" do
      let(:skill) { create(:skill, name: "deep_research") }

      before do
        agent.skills << skill
      end

      it "resolves load_skill as a system tool" do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.success(data: { output: skill.content })
        )

        post :execute, params: { tool_name: "load_skill", agent_id: agent.id, session_id: session.id, input: { name: "deep_research" } }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["success"]).to be true
        expect(Tools::Executor).to have_received(:call).with(
          tool: SystemTool::LOAD_SKILL,
          input: { "name" => "deep_research" },
          agent: agent,
          session: session
        )
      end

      it "does not broadcast tool events for system tools (handled by SDK proxy)" do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.success(data: { output: "skill content" })
        )

        post :execute, params: { tool_name: "load_skill", agent_id: agent.id, session_id: session.id, input: { name: "deep_research" } }

        expect(ActionCable.server).not_to have_received(:broadcast)
      end
    end

    context "with an unknown tool" do
      it "returns 422 with error message" do
        post :execute, params: { tool_name: "nonexistent_tool", agent_id: agent.id, session_id: session.id, input: {} }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to eq("Unknown tool: nonexistent_tool")
      end
    end

    context "with missing agent or session" do
      let(:tool) { create(:tool, enabled: true) }

      it "returns 422 when agent not found" do
        post :execute, params: { tool_name: tool.name, agent_id: -1, session_id: session.id, input: {} }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to eq("Agent or session not found")
      end

      it "returns 422 when session not found" do
        post :execute, params: { tool_name: tool.name, agent_id: agent.id, session_id: -1, input: {} }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to eq("Agent or session not found")
      end
    end

    context "authentication" do
      it "rejects requests without valid token" do
        request.headers["Authorization"] = "Bearer wrong-secret"

        post :execute, params: { tool_name: "anything", agent_id: agent.id, session_id: session.id, input: {} }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 503 when INTERNAL_API_SECRET is not configured" do
        allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(nil)

        post :execute, params: { tool_name: "anything", agent_id: agent.id, session_id: session.id, input: {} }

        expect(response).to have_http_status(:service_unavailable)
      end
    end
  end
end
