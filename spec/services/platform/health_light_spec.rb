# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::HealthLight do
  include ActiveJob::TestHelper

  def check(key, ok:, critical:)
    described_class::Check.new(key: key, label: key, ok: ok, detail: "x", critical: critical)
  end

  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:service_health) { instance_double(Platform::ServiceHealth, redis_connected?: true, sidekiq_running?: true) }

  before do
    allow(Rails).to receive(:cache).and_return(store)
    allow(Platform::ServiceHealth).to receive(:new).and_return(service_health)
  end

  describe ".rollup" do
    it "is green when every check passes" do
      expect(described_class.rollup([ check("a", ok: true, critical: true), check("b", ok: true, critical: false) ])).to eq(:green)
    end

    it "is green with no checks" do
      expect(described_class.rollup([])).to eq(:green)
    end

    it "is amber when only an optional check fails" do
      checks = [ check("claude", ok: true, critical: true), check("studio", ok: false, critical: false) ]
      expect(described_class.rollup(checks)).to eq(:amber)
    end

    it "is red when a critical check fails, even beside an optional failure" do
      checks = [ check("claude", ok: false, critical: true), check("studio", ok: false, critical: false) ]
      expect(described_class.rollup(checks)).to eq(:red)
    end
  end

  describe ".refresh!" do
    before do
      allow(Providers::AnthropicAdapter).to receive(:sdk_proxy_enabled?).and_return(true)
      allow(described_class).to receive(:fetch_json).and_return({ "degraded" => false })
    end

    it "caches a green snapshot when everything works" do
      result = described_class.refresh!

      expect(result[:status]).to eq(:green)
      expect(store.read(described_class::CACHE_KEY)[:checks].map { |c| c[:label] }).to include("Claude", "Background jobs", "Redis")
    end

    it "reports Claude as red when the proxy is unreachable" do
      allow(described_class).to receive(:fetch_json).and_return(nil)

      result = described_class.refresh!

      expect(result[:status]).to eq(:red)
      expect(result[:checks].find { |c| c[:key] == "claude" }[:detail]).to eq("not reachable")
    end

    it "reports Claude as red when the proxy has paused calls" do
      allow(described_class).to receive(:fetch_json).and_return({ "degraded" => true })

      expect(described_class.refresh![:status]).to eq(:red)
    end

    it "reports the Studio brain as amber when unreachable" do
      create(:provider_config, name: "studio", adapter_type: "ollama", base_url: "http://studio.invalid:11434")
      allow(described_class).to receive(:fetch_json).with(%r{/api/tags}).and_return(nil)

      result = described_class.refresh!

      expect(result[:status]).to eq(:amber)
      expect(result[:checks].find { |c| c[:key] == "studio" }).to include(ok: false, detail: "not reachable")
    end

    it "reports a stopped worker as red" do
      allow(service_health).to receive(:sidekiq_running?).and_return(false)

      expect(described_class.refresh![:status]).to eq(:red)
    end

    it "skips the Claude check when the proxy is off" do
      allow(Providers::AnthropicAdapter).to receive(:sdk_proxy_enabled?).and_return(false)

      expect(described_class.refresh![:checks].map { |c| c[:key] }).not_to include("claude")
    end
  end

  describe "timeouts" do
    it "turns a hanging Studio brain into not reachable quickly" do
      stub_const("Platform::HealthLight::CHECK_TIMEOUT", 0.1)
      create(:provider_config, name: "studio", adapter_type: "ollama", base_url: "http://studio.invalid:11434")
      allow(Net::HTTP).to receive(:start) { sleep 5 }
      allow(Providers::AnthropicAdapter).to receive(:sdk_proxy_enabled?).and_return(false)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = described_class.refresh!
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < 1
      expect(result[:checks].find { |c| c[:key] == "studio" }[:detail]).to eq("not reachable")
      expect(result[:status]).to eq(:amber)
    end
  end

  describe ".snapshot" do
    it "returns nil and queues one refresh when nothing is cached" do
      expect { 2.times { expect(described_class.snapshot).to be_nil } }
        .to have_enqueued_job(HealthLightRefreshJob).exactly(:once)
    end

    it "returns a fresh snapshot without queueing a refresh" do
      store.write(described_class::CACHE_KEY, { status: :green, checks: [], checked_at: Time.current })

      expect { expect(described_class.snapshot[:status]).to eq(:green) }.not_to have_enqueued_job(HealthLightRefreshJob)
    end

    it "returns a stale snapshot and queues a refresh" do
      store.write(described_class::CACHE_KEY, { status: :green, checks: [], checked_at: 2.minutes.ago })

      expect { expect(described_class.snapshot[:status]).to eq(:green) }.to have_enqueued_job(HealthLightRefreshJob)
    end

    it "renders red with a stopped-jobs line when the snapshot is too old" do
      store.write(described_class::CACHE_KEY, { status: :green, checks: [], checked_at: 4.minutes.ago })

      snapshot = described_class.snapshot

      expect(snapshot[:status]).to eq(:red)
      expect(snapshot[:checks]).to contain_exactly(
        include(label: "Background jobs", detail: "not running (health checks have stopped)")
      )
    end

    it "keeps a snapshot just under the stale limit as is" do
      store.write(described_class::CACHE_KEY, { status: :green, checks: [], checked_at: 2.minutes.ago })

      expect(described_class.snapshot[:status]).to eq(:green)
    end

    it "renders red with Redis not reachable when the cache read raises" do
      allow(store).to receive(:read).and_raise(Redis::CannotConnectError)

      snapshot = described_class.snapshot

      expect(snapshot[:status]).to eq(:red)
      expect(snapshot[:checks]).to contain_exactly(include(label: "Redis", detail: "not reachable"))
    end
  end
end
