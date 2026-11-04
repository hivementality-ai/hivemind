# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::ErrorClassifier, type: :service do
  describe "the 2026-08-24 incident error" do
    let(:message) do
      "Anthropic API error (400): You're out of extra usage. " \
      "Add more at claude.ai/settings/usage and keep going."
    end

    it "is permanent, not transient" do
      error = described_class.call(message: message)

      expect(error).to be_a(PermanentProviderError)
      expect(error.retryable?).to be(false)
      expect(error.reason).to eq("quota_exhausted")
    end

    it "opens the circuit" do
      expect(described_class.opens_circuit?(described_class.call(message: message))).to be(true)
    end
  end

  describe "status-driven classification" do
    {
      401 => "auth_invalid",
      403 => "forbidden",
      404 => "model_not_found",
      413 => "request_too_large",
      422 => "invalid_request"
    }.each do |status, reason|
      it "treats #{status} as permanent (#{reason})" do
        error = described_class.call(message: "nope", status: status)
        expect(error).to be_a(PermanentProviderError)
        expect(error.reason).to eq(reason)
      end
    end

    {
      408 => "timeout",
      409 => "conflict",
      429 => "rate_limited",
      500 => "server_error",
      503 => "server_error",
      529 => "server_error"
    }.each do |status, reason|
      it "treats #{status} as transient (#{reason})" do
        error = described_class.call(message: "nope", status: status)
        expect(error).to be_a(TransientProviderError)
        expect(error.reason).to eq(reason)
      end
    end

    it "distinguishes a quota 400 from an ordinary bad request" do
      quota = described_class.call(message: "You're out of extra usage.", status: 400)
      bad = described_class.call(message: "messages: at least one message is required", status: 400)

      expect(quota.reason).to eq("quota_exhausted")
      expect(bad.reason).to eq("invalid_request")
      expect([ quota, bad ]).to all(be_a(PermanentProviderError))
    end
  end

  describe "text-driven classification when no status is available" do
    it "recovers the status embedded in an adapter's error string" do
      error = described_class.from_error_string("SDK proxy error (429): rate limited")
      expect(error).to be_a(TransientProviderError)
      expect(error.reason).to eq("rate_limited")
    end

    it "classifies local port exhaustion as permanent" do
      error = described_class.from_error_string("Failed to open TCP connection: Can't assign requested address")

      expect(error).to be_a(PermanentProviderError)
      expect(error.reason).to eq("local_port_exhaustion")
      expect(described_class.opens_circuit?(error)).to be(true)
    end

    it "keeps ordinary socket errors retryable" do
      error = described_class.from_error_string("Connection refused - connect(2) for api.anthropic.com")
      expect(error).to be_a(TransientProviderError)
      expect(error.reason).to eq("network_error")
    end

    it "defaults the unclassifiable to permanent" do
      # Treating the unknown as retryable is what turned one bad credential
      # into a host-wide outage.
      error = described_class.from_error_string("Claude Code process exited with code 1")

      expect(error).to be_a(PermanentProviderError)
      expect(error.reason).to eq("unknown")
      expect(described_class.opens_circuit?(error)).to be(false),
             "unknown must not open the circuit on its own"
    end
  end

  describe "structured proxy bodies" do
    it "trusts the proxy's verdict verbatim" do
      body = { "reason" => "quota_exhausted", "retryable" => false,
               "error" => { "message" => "out of extra usage" } }
      error = described_class.call(message: "SDK proxy error (402)", status: 402, body: body)

      expect(error).to be_a(PermanentProviderError)
      expect(error.reason).to eq("quota_exhausted")
    end

    it "does not re-derive a 503 from an open circuit as a retryable server error" do
      body = '{"reason":"quota_exhausted","retryable":false}'
      error = described_class.call(message: "provider circuit open", status: 503, body: body)

      expect(error).to be_a(PermanentProviderError)
      expect(error.reason).to eq("quota_exhausted")
    end

    it "honours a retryable verdict from the proxy" do
      body = { "reason" => "load_shed", "retryable" => true, "retry_after_ms" => 5000 }
      error = described_class.call(message: "at capacity", status: 429, body: body)

      expect(error).to be_a(TransientProviderError)
      expect(error.retry_after).to eq(5)
    end

    it "falls back to deriving when the body is not structured" do
      error = described_class.call(message: "boom", status: 429, body: "<html>bad gateway</html>")
      expect(error.reason).to eq("rate_limited")
    end
  end

  it "agrees with the sdk-proxy on which reasons open a circuit" do
    # Mirrors CIRCUIT_REASONS in sdk-proxy/error-classifier.js.
    expect(described_class::CIRCUIT_REASONS).to contain_exactly(
      "quota_exhausted", "auth_invalid", "forbidden", "local_port_exhaustion"
    )
  end
end
