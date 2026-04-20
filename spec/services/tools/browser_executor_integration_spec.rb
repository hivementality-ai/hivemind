# frozen_string_literal: true

require "rails_helper"

# Integration spec: verifies BrowserExecutor is correctly wired into the
# Executor dispatch layer and that the full call path works end-to-end
# (sidecar HTTP calls stubbed at Net::HTTP level).

RSpec.describe "Tools::Executor browser dispatch", type: :service do
  let(:agent)   { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:tool)    { create(:tool, :browser_tool) }

  def stub_sidecar_sequence(*responses)
    call_count = 0
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request) do
      resp = instance_double(Net::HTTPResponse)
      body = responses[call_count] || responses.last
      call_count += 1
      allow(resp).to receive(:body).and_return(body.to_json)
      resp
    end
  end

  def page_state_payload
    {
      url: "https://example.com",
      title: "Integration Test",
      elements: [
        { index: 1, tag: "input", type: "text", name: "q" },
        { index: 2, tag: "button", text: "Search" }
      ],
      text_summary: "Hello from the page",
      scroll_y: 0,
      page_height: 1000,
      viewport_height: 720
    }
  end

  def seed_redis_session(hivemind_session, session_id: "testses123456")
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://cache:6379/0"))
    redis.set("browser_session:#{hivemind_session.id}", session_id, ex: 300)
  rescue StandardError
    nil
  end

  def clear_redis_session(hivemind_session)
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://cache:6379/0"))
    redis.del("browser_session:#{hivemind_session.id}")
  rescue StandardError
    nil
  end

  # Prevent Redis state from bleeding between examples
  after { clear_redis_session(session) }

  # ── Executor registration ─────────────────────────────────────────────────

  describe "executor registration" do
    it "has browser mapped to BrowserExecutor" do
      expect(Tools::Executor::BUILTIN_EXECUTORS["browser"]).to eq(Tools::BrowserExecutor)
    end

    it "treats browser as a network executor type (egress-checked)" do
      expect(Tools::Executor::NETWORK_EXECUTOR_TYPES).to include("browser")
    end
  end

  # ── Full dispatch — navigate ───────────────────────────────────────────────

  describe "full dispatch via Tools::Executor.call — navigate" do
    context "successful navigate (session pre-seeded)" do
      before do
        seed_redis_session(session)
        stub_sidecar_sequence({ success: true, state: page_state_payload })
      end

      it "creates a ToolExecution record and returns formatted output" do
        expect {
          @result = Tools::Executor.call(
            tool: tool,
            input: { "action" => "navigate", "url" => "https://example.com" },
            agent: agent,
            session: session
          )
        }.to change { ToolExecution.count }.by(1)

        expect(@result).to be_success
        expect(@result.data[:output]).to include("URL: https://example.com")
        expect(@result.data[:output]).to include("Title: Integration Test")
        expect(@result.data[:output]).to include("[1] input")
        expect(@result.data[:output]).to include("[2] button")
        expect(@result.data[:output]).to include("Hello from the page")
      end

      it "marks execution as completed with exit_code 0" do
        Tools::Executor.call(
          tool: tool,
          input: { "action" => "navigate", "url" => "https://example.com" },
          agent: agent,
          session: session
        )

        exec = ToolExecution.last
        expect(exec.status).to eq("completed")
        expect(exec.exit_code).to eq(0)
      end
    end

    context "navigate with auto session creation" do
      before do
        # First call creates session, second call navigates
        stub_sidecar_sequence(
          { session_id: "newsession123" },
          { success: true, state: page_state_payload }
        )
      end

      it "creates session automatically and returns output" do
        result = Tools::Executor.call(
          tool: tool,
          input: { "action" => "navigate", "url" => "https://example.com" },
          agent: agent,
          session: session
        )

        expect(result).to be_success
        expect(result.data[:output]).to include("URL: https://example.com")
      end
    end

    context "sidecar returns failure" do
      before do
        seed_redis_session(session)
        stub_sidecar_sequence({ success: false, error: "Page load timeout" })
      end

      it "marks execution as failed" do
        Tools::Executor.call(
          tool: tool,
          input: { "action" => "navigate", "url" => "https://example.com" },
          agent: agent,
          session: session
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
          tool: tool,
          input: { "action" => "navigate", "url" => "" },
          agent: agent,
          session: session
        )

        expect(result).not_to be_success
        expect(result.error).to eq("No URL provided")
      end
    end
  end

  # ── Full dispatch — click ──────────────────────────────────────────────────

  describe "full dispatch — click" do
    before do
      seed_redis_session(session)
      stub_sidecar_sequence({ success: true, message: "Clicked element 1", state: page_state_payload })
    end

    it "creates execution record and returns click result" do
      result = Tools::Executor.call(
        tool: tool,
        input: { "action" => "click", "index" => 1 },
        agent: agent,
        session: session
      )

      expect(result).to be_success
      expect(result.data[:output]).to include("Clicked element 1")
      expect(ToolExecution.last.status).to eq("completed")
    end
  end

  # ── Full dispatch — done ───────────────────────────────────────────────────

  describe "full dispatch — done" do
    before do
      seed_redis_session(session)
      stub_sidecar_sequence({ success: true })
    end

    it "closes session and returns confirmation" do
      result = Tools::Executor.call(
        tool: tool,
        input: { "action" => "done" },
        agent: agent,
        session: session
      )

      expect(result).to be_success
      expect(result.data[:output]).to eq("Browser session closed.")
    end
  end
end
