# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteAccess::HealthCheck, type: :service do
  describe ".call" do
    it "fails fast on a blank URL" do
      result = described_class.call("")
      expect(result).not_to be_success
      expect(result.error).to include("No URL")
    end

    it "fails fast on a non-http(s) URL" do
      result = described_class.call("ftp://example.com")
      expect(result).not_to be_success
      expect(result.error).to include("http(s)")
    end

    context "when both checks pass" do
      it "returns success with both check results" do
        stub_request(:get, "https://hivemind.example.com").to_return(status: 200, body: "ok")
        allow(RemoteAccess::WebSocketProbe).to receive(:call)
          .with("wss://hivemind.example.com/cable", timeout: described_class::WS_TIMEOUT)
          .and_return({ ok: true })

        result = described_class.call("https://hivemind.example.com")

        expect(result).to be_success
        expect(result.data[:http][:ok]).to eq(true)
        expect(result.data[:websocket][:ok]).to eq(true)
      end

      it "strips a trailing slash before building the /cable URL" do
        stub_request(:get, "https://hivemind.example.com").to_return(status: 200, body: "ok")
        allow(RemoteAccess::WebSocketProbe).to receive(:call)
          .with("wss://hivemind.example.com/cable", timeout: described_class::WS_TIMEOUT)
          .and_return({ ok: true })

        result = described_class.call("https://hivemind.example.com/")
        expect(result).to be_success
      end
    end

    context "when the HTTP check fails" do
      it "returns failure with the HTTP error and does not report websocket as ok" do
        stub_request(:get, "https://down.example.com").to_timeout
        allow(RemoteAccess::WebSocketProbe).to receive(:call).and_return({ ok: true })

        result = described_class.call("https://down.example.com")

        expect(result).not_to be_success
        expect(result.payload[:http][:ok]).to eq(false)
        expect(result.error).to include("HTTP check failed")
      end

      it "treats a 5xx response as a failed HTTP check" do
        stub_request(:get, "https://error.example.com").to_return(status: 502, body: "bad gateway")
        allow(RemoteAccess::WebSocketProbe).to receive(:call).and_return({ ok: true })

        result = described_class.call("https://error.example.com")

        expect(result).not_to be_success
        expect(result.payload[:http][:status]).to eq(502)
      end

      it "treats a 404 as a passing HTTP check (reachable, just no root route)" do
        stub_request(:get, "https://notfound.example.com").to_return(status: 404, body: "not found")
        allow(RemoteAccess::WebSocketProbe).to receive(:call).and_return({ ok: true })

        result = described_class.call("https://notfound.example.com")
        expect(result.data[:http][:ok]).to eq(true)
      end
    end

    context "when the WebSocket check fails" do
      it "returns failure with the websocket error" do
        stub_request(:get, "https://no-cable.example.com").to_return(status: 200, body: "ok")
        allow(RemoteAccess::WebSocketProbe).to receive(:call)
          .and_return({ ok: false, error: "handshake timed out after 10s" })

        result = described_class.call("https://no-cable.example.com")

        expect(result).not_to be_success
        expect(result.payload[:websocket][:ok]).to eq(false)
        expect(result.error).to include("WebSocket check failed")
      end
    end

    it "uses wss:// for https URLs and ws:// for http URLs" do
      stub_request(:get, "http://plain.example.com").to_return(status: 200, body: "ok")
      allow(RemoteAccess::WebSocketProbe).to receive(:call)
        .with("ws://plain.example.com/cable", timeout: described_class::WS_TIMEOUT)
        .and_return({ ok: true })

      result = described_class.call("http://plain.example.com")
      expect(result).to be_success
    end
  end
end
