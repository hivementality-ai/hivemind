# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::CircuitBreaker, type: :service do
  let(:credential) { "sk-ant-oat01-test-token" }
  let(:breaker) { described_class.new(provider: "anthropic", credential: credential) }

  let(:quota_error) do
    Providers::ErrorClassifier.call(
      message: "You're out of extra usage. Add more at claude.ai/settings/usage",
      status: 400
    )
  end
  let(:transient_error) { Providers::ErrorClassifier.call(message: "overloaded", status: 529) }

  before do
    described_class.reset_all!
    allow(described_class).to receive(:threshold).and_return(3)
    allow(described_class).to receive(:open_seconds).and_return(900)
    # The sdk-proxy is not running under test.
    allow(described_class).to receive(:reset_sdk_proxy!)
  end

  after { described_class.reset_all! }

  describe "#check!" do
    it "allows calls while closed" do
      expect { breaker.check! }.not_to raise_error
    end

    it "refuses to dial once the threshold is crossed" do
      3.times { breaker.record_failure(quota_error) }

      expect { breaker.check! }.to raise_error(ProviderCircuitOpenError) do |error|
        expect(error.retryable?).to be(false)
        expect(error.reason).to eq("quota_exhausted")
        expect(error.message).to include("out of usage credit")
      end
    end

    it "allows the attempts below the threshold" do
      2.times { breaker.record_failure(quota_error) }
      expect { breaker.check! }.not_to raise_error
    end
  end

  describe "#record_failure" do
    it "never opens on transient failures" do
      50.times { breaker.record_failure(transient_error) }

      expect(breaker.state).to be_closed
      expect { breaker.check! }.not_to raise_error
    end

    it "does not open on a caller-side bug that would fail on any credential" do
      bad_request = Providers::ErrorClassifier.call(message: "messages required", status: 422)
      5.times { breaker.record_failure(bad_request) }

      expect(breaker.state).to be_closed
    end

    it "logs one alarm line when it opens" do
      allow(Rails.logger).to receive(:error)
      3.times { breaker.record_failure(quota_error) }

      expect(Rails.logger).to have_received(:error).with(/\[ALARM\].*circuit OPEN.*quota_exhausted/).once
    end

    it "records an audit entry when it opens" do
      expect { 3.times { breaker.record_failure(quota_error) } }
        .to change { AuditLog.where(action: "provider_circuit_opened").count }.by(1)
    end
  end

  describe "half-open probing" do
    before { 3.times { breaker.record_failure(quota_error) } }

    it "stays open for the cooldown" do
      travel_to(14.minutes.from_now) { expect { breaker.check! }.to raise_error(ProviderCircuitOpenError) }
    end

    it "lets exactly one probe through after the cooldown" do
      travel_to(16.minutes.from_now) do
        expect(breaker.state).to be_half_open
        expect { breaker.check! }.not_to raise_error
      end
    end

    it "re-opens immediately when the probe fails" do
      travel_to(16.minutes.from_now) do
        breaker.record_failure(quota_error)
        expect { breaker.check! }.to raise_error(ProviderCircuitOpenError)
      end
    end

    it "closes when the probe succeeds" do
      travel_to(16.minutes.from_now) do
        breaker.record_success
        expect(breaker.state).to be_closed
        expect { breaker.check! }.not_to raise_error
      end
    end
  end

  describe "isolation" do
    it "one exhausted credential does not silence another" do
      3.times { breaker.record_failure(quota_error) }
      healthy = described_class.new(provider: "anthropic", credential: "sk-ant-oat01-other")

      expect { breaker.check! }.to raise_error(ProviderCircuitOpenError)
      expect { healthy.check! }.not_to raise_error
    end

    it "one exhausted provider does not silence another" do
      3.times { breaker.record_failure(quota_error) }
      other = described_class.new(provider: "openai", credential: credential)

      expect { other.check! }.not_to raise_error
    end

    it "never stores the raw credential" do
      3.times { breaker.record_failure(quota_error) }
      stored = Redis.current.keys("#{described_class::NAMESPACE}:*").join(" ")

      expect(stored).not_to include(credential)
      expect(described_class.open_circuits.first.credential).not_to include("test-token")
    end
  end

  describe ".guard" do
    it "runs the block and closes on success" do
      result = described_class.guard(provider: "anthropic", credential: credential) { :served }
      expect(result).to eq(:served)
    end

    it "raises before the block runs once open" do
      3.times { breaker.record_failure(quota_error) }
      called = false

      expect {
        described_class.guard(provider: "anthropic", credential: credential) { called = true }
      }.to raise_error(ProviderCircuitOpenError)

      expect(called).to be(false), "an open circuit must not reach the network"
    end
  end

  describe ".open_circuits" do
    it "is empty when everything is healthy" do
      expect(described_class.open_circuits).to be_empty
    end

    it "surfaces the reason and failure count for the UI banner" do
      3.times { breaker.record_failure(quota_error) }
      circuit = described_class.open_circuits.first

      expect(circuit.provider).to eq("anthropic")
      expect(circuit.reason).to eq("quota_exhausted")
      expect(circuit.failures).to eq(3)
      expect(circuit.opened_at).to be_present
    end
  end

  describe ".reset_provider!" do
    it "restores service immediately when a human fixes the credential" do
      3.times { breaker.record_failure(quota_error) }
      described_class.reset_provider!("anthropic")

      expect { breaker.check! }.not_to raise_error
      expect(described_class.open_circuits).to be_empty
    end

    it "leaves other providers alone" do
      other = described_class.new(provider: "openai", credential: credential)
      3.times { breaker.record_failure(quota_error) }
      3.times { other.record_failure(quota_error) }

      described_class.reset_provider!("anthropic")

      expect { breaker.check! }.not_to raise_error
      expect { other.check! }.to raise_error(ProviderCircuitOpenError)
    end
  end

  describe "Redis unavailability" do
    it "fails open so a Redis blip never blocks a working provider" do
      allow(Redis).to receive(:current).and_raise(Redis::CannotConnectError)

      expect { breaker.check! }.not_to raise_error
      expect(breaker.state).to be_closed
    end
  end
end
