# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Executor, "egress controls" do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }

  let(:web_fetch_tool) do
    create(:tool, executor_type: "web_fetch", name: "web_fetch")
  end

  let(:http_request_tool) do
    create(:tool, executor_type: "http_request", name: "http_request")
  end

  let(:browser_tool) do
    create(:tool, :browser_tool)
  end

  let(:shell_tool) do
    create(:tool, :shell_tool)
  end

  context "when agent has allowlist policy" do
    before do
      agent.update!(egress_policy: {
        "mode" => "allowlist",
        "rules" => [{ "pattern" => "api.allowed.com" }],
        "log_blocked" => false
      })
    end

    it "blocks web_fetch to disallowed domain" do
      result = described_class.call(
        tool: web_fetch_tool,
        input: { "url" => "https://evil.com/steal" },
        agent: agent,
        session: session
      )

      expect(result.success?).to be false
      expect(result.error).to include("Egress blocked")
    end

    it "allows web_fetch to allowed domain" do
      # Stub the actual executor to avoid real HTTP calls
      allow_any_instance_of(Tools::WebFetchExecutor).to receive(:call)
        .and_return(ServiceResponse.success(data: { output: "OK", exit_code: 0 }))

      result = described_class.call(
        tool: web_fetch_tool,
        input: { "url" => "https://api.allowed.com/data" },
        agent: agent,
        session: session
      )

      expect(result.success?).to be true
    end

    it "blocks http_request to disallowed domain" do
      result = described_class.call(
        tool: http_request_tool,
        input: { "url" => "https://blocked.com/api" },
        agent: agent,
        session: session
      )

      expect(result.success?).to be false
      expect(result.error).to include("Egress blocked")
    end

    it "blocks browser to disallowed domain" do
      result = described_class.call(
        tool: browser_tool,
        input: { "url" => "https://blocked.com", "action" => "navigate" },
        agent: agent,
        session: session
      )

      expect(result.success?).to be false
      expect(result.error).to include("Egress blocked")
    end

    it "sets execution status to blocked" do
      described_class.call(
        tool: web_fetch_tool,
        input: { "url" => "https://evil.com/steal" },
        agent: agent,
        session: session
      )

      execution = ToolExecution.last
      expect(execution.status).to eq("blocked")
      expect(execution.error).to include("Egress blocked")
    end
  end

  context "when agent has no egress policy" do
    it "allows all network requests" do
      allow_any_instance_of(Tools::WebFetchExecutor).to receive(:call)
        .and_return(ServiceResponse.success(data: { output: "OK", exit_code: 0 }))

      result = described_class.call(
        tool: web_fetch_tool,
        input: { "url" => "https://anything.com" },
        agent: agent,
        session: session
      )

      expect(result.success?).to be true
    end
  end

  context "with non-network tools" do
    before do
      agent.update!(egress_policy: {
        "mode" => "allowlist",
        "rules" => [{ "pattern" => "api.allowed.com" }],
        "log_blocked" => false
      })
    end

    it "does not check egress policy for shell tool" do
      allow_any_instance_of(Tools::ShellExecutor).to receive(:call)
        .and_return(ServiceResponse.success(data: { output: "OK", exit_code: 0 }))

      result = described_class.call(
        tool: shell_tool,
        input: { "command" => "echo hello" },
        agent: agent,
        session: session
      )

      expect(result.success?).to be true
    end
  end
end
