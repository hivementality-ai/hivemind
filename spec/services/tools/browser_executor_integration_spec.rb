# frozen_string_literal: true

require "rails_helper"

# Integration spec: verifies BrowserExecutor is correctly wired into the
# Executor dispatch layer and that the full call path works end-to-end
# (sidecar HTTP call stubbed at Net::HTTP level).

RSpec.describe "Tools::Executor browser dispatch", type: :service do
  let(:agent)   { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:tool)    { create(:tool, :browser_tool) }

  def stub_sidecar_navigate(response_body)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)

    resp = instance_double(Net::HTTPResponse)
    allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(resp).to receive(:body).and_return(response_body.to_json)
    allow(http).to receive(:request).and_return(resp)
  end

  describe "executor registration" do
    it "has browser mapped to BrowserExecutor" do
      expect(Tools::Executor::BUILTIN_EXECUTORS["browser"]).to eq(Tools::BrowserExecutor)
    end

    it "treats browser as a network executor type (egress-checked)" do
      expect(Tools::Executor::NETWORK_EXECUTOR_TYPES).to include("browser")
    end
  end

  describe "full dispatch via Tools::Executor.call" do
    context "successful navigate" do
      before do
        stub_sidecar_navigate({
          success: true,
          title: "Integration Test",
          url: "https://example.com",
          content: "Hello from the page"
        })
      end

      it "creates a ToolExecution record and returns output" do
        expect {
          @result = Tools::Executor.call(
            tool: tool, input: { "action" => "navigate", "url" => "https://example.com" },
            agent: agent, session: session
          )
        }.to change { ToolExecution.count }.by(1)

        expect(@result).to be_success
        expect(@result.data[:output]).to include("Title: Integration Test")
        expect(@result.data[:output]).to include("Hello from the page")
      end

      it "marks execution as completed" do
        Tools::Executor.call(
          tool: tool, input: { "action" => "navigate", "url" => "https://example.com" },
          agent: agent, session: session
        )

        exec = ToolExecution.last
        expect(exec.status).to eq("completed")
        expect(exec.exit_code).to eq(0)
      end
    end

    context "sidecar returns failure" do
      before do
        stub_sidecar_navigate({ success: false, error: "Page load timeout" })
      end

      it "marks execution as failed" do
        Tools::Executor.call(
          tool: tool, input: { "action" => "navigate", "url" => "https://example.com" },
          agent: agent, session: session
        )

        exec = ToolExecution.last
        expect(exec.status).to eq("failed")
        expect(exec.error).to eq("Page load timeout")
      end
    end

    context "missing URL" do
      it "fails before hitting sidecar" do
        expect(Net::HTTP).not_to receive(:new)

        result = Tools::Executor.call(
          tool: tool, input: { "action" => "navigate", "url" => "" },
          agent: agent, session: session
        )

        expect(result).not_to be_success
        expect(result.error).to eq("No URL provided")
      end
    end
  end
end
