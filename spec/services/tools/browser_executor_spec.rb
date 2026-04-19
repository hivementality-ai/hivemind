# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::BrowserExecutor, type: :service do
  subject(:executor) { described_class.new(input: input, config: config) }

  # Shared config with a stub session — needed for Redis session key
  let(:hivemind_session) { create(:session) }
  let(:config)           { { session: hivemind_session } }

  # ── Sidecar stub helpers ──────────────────────────────────────────────────

  def stub_sidecar_post(path_suffix, response_body)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)

    resp = instance_double(Net::HTTPResponse)
    allow(resp).to receive(:body).and_return(response_body.to_json)
    allow(http).to receive(:request).and_return(resp)
    resp
  end

  # Stubs session create then a second call in sequence
  def stub_session_create_then(second_response)
    call_count = 0
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)

    allow(http).to receive(:request) do
      call_count += 1
      resp = instance_double(Net::HTTPResponse)
      body = call_count == 1 ? { session_id: "abc123def456" } : second_response
      allow(resp).to receive(:body).and_return(body.to_json)
      resp
    end
  end

  def page_state_payload
    {
      url: "https://example.com",
      title: "Example",
      elements: [
        { index: 1, tag: "input", type: "text", name: "q", placeholder: "Search" },
        { index: 2, tag: "button", text: "Go" }
      ],
      text_summary: "Welcome to example.com",
      scroll_y: 0,
      page_height: 1200,
      viewport_height: 720
    }
  end

  def success_state_response
    { success: true, state: page_state_payload }
  end

  # Pre-seed Redis with a session_id so most tests don't need to stub create
  def seed_redis_session(session_id: "abc123def456")
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://cache:6379/0"))
    redis.set("browser_session:#{hivemind_session.id}", session_id, ex: 300)
  rescue StandardError
    # Redis not available in test env — executor handles nil redis gracefully
  end

  # ── Input validation ──────────────────────────────────────────────────────

  describe "#call — input validation" do
    context "navigate with no URL" do
      let(:input) { { "action" => "navigate", "url" => "" } }

      it "returns failure without hitting sidecar" do
        expect(Net::HTTP).not_to receive(:new)
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No URL provided")
      end
    end

    context "click with no index" do
      let(:input) { { "action" => "click", "index" => 0 } }

      before { seed_redis_session }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No element index provided")
      end
    end

    context "type with no index" do
      let(:input) { { "action" => "type", "index" => 0, "text" => "hello" } }

      before { seed_redis_session }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No element index provided")
      end
    end

    context "type with no text" do
      let(:input) { { "action" => "type", "index" => 1, "text" => "" } }

      before { seed_redis_session }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No text provided")
      end
    end

    context "keys with no keys string" do
      let(:input) { { "action" => "keys", "keys" => "" } }

      before { seed_redis_session }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No keys provided")
      end
    end

    context "unknown action" do
      let(:input) { { "action" => "teleport" } }

      before { seed_redis_session }

      it "returns failure with list of valid actions" do
        stub_sidecar_post(nil, {})
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to include("Unknown action: teleport")
        expect(result.error).to include("navigate")
        expect(result.error).to include("done")
      end
    end
  end

  # ── navigate ─────────────────────────────────────────────────────────────

  describe "#call — navigate" do
    let(:input) { { "action" => "navigate", "url" => "https://example.com" } }

    before { seed_redis_session }

    context "sidecar returns state" do
      before { stub_sidecar_post("/navigate", success_state_response) }

      it "returns success with formatted state output" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Navigated to https://example.com")
        expect(result.data[:output]).to include("URL: https://example.com")
        expect(result.data[:output]).to include("Title: Example")
        expect(result.data[:output]).to include("[1] input")
        expect(result.data[:output]).to include("[2] button")
        expect(result.data[:exit_code]).to eq(0)
      end

      it "includes scroll position" do
        result = executor.call
        expect(result.data[:output]).to include("Scroll: 0/1200px")
      end

      it "includes page text summary" do
        result = executor.call
        expect(result.data[:output]).to include("Page text: Welcome to example.com")
      end
    end

    context "blank action defaults to navigate" do
      let(:input) { { "action" => "", "url" => "https://example.com" } }

      before { stub_sidecar_post("/navigate", success_state_response) }

      it "returns success" do
        result = executor.call
        expect(result).to be_success
      end
    end

    context "'get' action treated as navigate" do
      let(:input) { { "action" => "get", "url" => "https://example.com" } }

      before { stub_sidecar_post("/navigate", success_state_response) }

      it "returns success" do
        result = executor.call
        expect(result).to be_success
      end
    end

    context "sidecar returns error" do
      before { stub_sidecar_post("/navigate", { success: false, error: "Navigation timeout" }) }

      it "returns failure with sidecar error" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Navigation timeout")
      end
    end

    context "no session in Redis (auto-creates one)" do
      it "calls session/create then navigates" do
        stub_session_create_then(success_state_response)
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("URL: https://example.com")
      end
    end
  end

  # ── state ─────────────────────────────────────────────────────────────────

  describe "#call — state" do
    let(:input) { { "action" => "state" } }

    before do
      seed_redis_session
      stub_sidecar_post("/state", success_state_response)
    end

    it "returns formatted element list" do
      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to include("Interactive elements:")
      expect(result.data[:output]).to include("[1] input")
      expect(result.data[:output]).to include("[2] button")
    end

    it "returns no-prefix header (no 'Navigated' line)" do
      result = executor.call
      expect(result.data[:output]).not_to include("Navigated")
    end
  end

  # ── click ─────────────────────────────────────────────────────────────────

  describe "#call — click" do
    let(:input) { { "action" => "click", "index" => 2 } }

    before do
      seed_redis_session
      stub_sidecar_post("/click", { success: true, message: "Clicked element 2", state: page_state_payload })
    end

    it "returns success with click confirmation" do
      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to include("Clicked element 2")
    end

    context "sidecar reports click failure" do
      before { stub_sidecar_post("/click", { success: false, error: "Element not found" }) }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Element not found")
      end
    end
  end

  # ── type ──────────────────────────────────────────────────────────────────

  describe "#call — type" do
    let(:input) { { "action" => "type", "index" => 1, "text" => "hello world" } }

    before do
      seed_redis_session
      stub_sidecar_post("/type", { success: true, message: "Typed into element 1", state: page_state_payload })
    end

    it "returns success with type confirmation" do
      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to include("Typed into element 1")
    end
  end

  # ── scroll ────────────────────────────────────────────────────────────────

  describe "#call — scroll" do
    let(:input) { { "action" => "scroll", "direction" => "down", "pages" => 2 } }

    before do
      seed_redis_session
      stub_sidecar_post("/scroll", success_state_response)
    end

    it "returns success with scrolled prefix" do
      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to include("Scrolled down")
    end
  end

  # ── keys ──────────────────────────────────────────────────────────────────

  describe "#call — keys" do
    let(:input) { { "action" => "keys", "keys" => "Enter" } }

    before do
      seed_redis_session
      stub_sidecar_post("/keys", { success: true, message: "Sent keys: Enter", state: page_state_payload })
    end

    it "returns success with keys confirmation" do
      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to include("Sent keys: Enter")
    end
  end

  # ── screenshot ────────────────────────────────────────────────────────────

  describe "#call — screenshot" do
    let(:input) { { "action" => "screenshot" } }
    let(:png_base64) { Base64.strict_encode64("fake_png_bytes") }

    before do
      seed_redis_session
      stub_sidecar_post("/screenshot", {
        success: true,
        screenshot_base64: png_base64,
        url: "https://example.com",
        title: "Example"
      })
      allow(File).to receive(:binwrite)
    end

    it "saves screenshot and returns path" do
      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to include("Screenshot saved:")
      expect(result.data[:output]).to include("URL: https://example.com")
      expect(result.data[:output]).to include("Title: Example")
    end

    context "sidecar failure" do
      before { stub_sidecar_post("/screenshot", { success: false, error: "Screenshot failed" }) }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Screenshot failed")
      end
    end
  end

  # ── extract ───────────────────────────────────────────────────────────────

  describe "#call — extract" do
    let(:input) { { "action" => "extract" } }

    before do
      seed_redis_session
      stub_sidecar_post("/extract", {
        success: true,
        content: "Full page content here",
        url: "https://example.com",
        title: "Example"
      })
    end

    it "returns full page text" do
      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to include("Full page content here")
      expect(result.data[:output]).to include("Title: Example")
    end

    context "sidecar failure" do
      before { stub_sidecar_post("/extract", { success: false, error: "Extract failed" }) }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Extract failed")
      end
    end
  end

  # ── done ──────────────────────────────────────────────────────────────────

  describe "#call — done" do
    let(:input) { { "action" => "done" } }

    before { seed_redis_session }

    it "closes session and returns confirmation" do
      stub_sidecar_post("/session/abc123def456", { success: true })
      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to eq("Browser session closed.")
    end

    it "succeeds even when no session exists" do
      # No Redis session — done should still succeed without hitting sidecar
      result = executor.call
      expect(result).to be_success
    end
  end

  # ── Network error paths ───────────────────────────────────────────────────

  describe "#call — network errors" do
    let(:input) { { "action" => "navigate", "url" => "https://example.com" } }

    before { seed_redis_session }

    context "connection refused" do
      before do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED, "Connection refused")
      end

      it "returns failure with helpful message" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to include("Browser sidecar not running")
      end
    end

    context "read timeout" do
      before do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).and_raise(Net::ReadTimeout)
      end

      it "returns failure with timeout message" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to include("timed out")
      end
    end

    context "invalid JSON response" do
      before do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        resp = instance_double(Net::HTTPResponse)
        allow(resp).to receive(:body).and_return("not {{ valid json")
        allow(http).to receive(:request).and_return(resp)
      end

      it "returns failure with parse error message" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Invalid response from browser sidecar")
      end
    end
  end

  # ── Element formatting ────────────────────────────────────────────────────

  describe "element formatting" do
    let(:input) { { "action" => "state" } }

    before { seed_redis_session }

    it "formats all element attribute combinations correctly" do
      stub_sidecar_post("/state", {
        success: true,
        state: {
          url: "https://example.com",
          title: "Test",
          elements: [
            { index: 1, tag: "input", type: "text", name: "q", placeholder: "Search" },
            { index: 2, tag: "a", text: "Click me", href: "https://example.com/page" },
            { index: 3, tag: "button", role: "button", aria_label: "Close dialog" },
            { index: 4, tag: "input", type: "submit", value: "Submit" }
          ],
          text_summary: "",
          scroll_y: 0,
          page_height: 800,
          viewport_height: 720
        }
      })

      result = executor.call
      expect(result).to be_success
      output = result.data[:output]
      expect(output).to include("[1] input type=text name=q")
      expect(output).to include("placeholder=\"Search\"")
      expect(output).to include("[2] a")
      expect(output).to include("\"Click me\"")
      expect(output).to include("→ https://example.com/page")
      expect(output).to include("[3] button role=button")
      expect(output).to include("(Close dialog)")
      expect(output).to include("[4] input type=submit")
      expect(output).to include("value=\"Submit\"")
    end

    it "shows no-elements message when list is empty" do
      stub_sidecar_post("/state", {
        success: true,
        state: {
          url: "https://example.com",
          title: "Blank",
          elements: [],
          text_summary: "",
          scroll_y: 0,
          page_height: 100,
          viewport_height: 720
        }
      })

      result = executor.call
      expect(result).to be_success
      expect(result.data[:output]).to include("(No interactive elements found)")
    end
  end
end
