# frozen_string_literal: true

require "rails_helper"

# Regression test for the 2026-08-24 host-wide port exhaustion.
#
# The provider is stubbed to return `400 "You're out of extra usage"` for every
# call — a permanently failing credential — and the stack is driven under load.
# The assertion is the one the incident failed: the number of attempts that
# actually reach the network must be bounded and countable, not a function of
# how long the outage lasts.
RSpec.describe "provider resource discipline", type: :service do
  let(:config) { double("Config", base_url: nil) }
  let(:api_key) { "sk-ant-oat01-exhausted-account" }
  let(:adapter) { Providers::AnthropicAdapter.new(config: config, api_key: api_key) }
  let(:proxy_client) { instance_double(Providers::Anthropic::SdkProxyClient) }

  # What the sdk-proxy sends once it has classified the failure.
  let(:quota_failure) do
    ServiceResponse.failure(
      error: "SDK proxy error (402): You're out of extra usage. Add more at claude.ai/settings/usage",
      payload: { provider_error: { message: "You're out of extra usage.", status: 402,
                                   reason: "quota_exhausted", provider: "anthropic", retryable: false } }
    )
  end

  before do
    Providers::CircuitBreaker.reset_all!
    allow(Providers::CircuitBreaker).to receive(:threshold).and_return(3)
    allow(Providers::CircuitBreaker).to receive(:reset_sdk_proxy!)
    allow(Providers::Anthropic::SdkProxyClient).to receive(:new).and_return(proxy_client)
    allow(proxy_client).to receive(:chat).and_return(quota_failure)
    allow(MemoryFileSyncJob).to receive(:perform_later)
  end

  after { Providers::CircuitBreaker.reset_all! }

  it "stops reaching the network after the threshold, however long the outage runs" do
    200.times { adapter.chat(messages: [ { role: "user", content: "hi" } ]) }

    expect(proxy_client).to have_received(:chat).exactly(3).times
  end

  it "reports the real reason once it stops dialling, not a generic error" do
    4.times { adapter.chat(messages: [ { role: "user", content: "hi" } ]) }
    result = adapter.chat(messages: [ { role: "user", content: "hi" } ])

    expect(result).to be_failure
    expect(result.error).to include("out of usage credit")
    expect(result.error).to include("claude.ai/settings/usage")
    expect(result.payload[:provider_error][:reason]).to eq("quota_exhausted")
    expect(result.payload[:provider_error][:retryable]).to be(false)
  end

  it "does not even enqueue the memory sync once the circuit is open" do
    syncs = 0
    allow(MemoryFileSyncJob).to receive(:perform_later) { syncs += 1 }

    3.times { adapter.chat(messages: [ { role: "user", content: "hi" } ], options: { agent_id: 1 }) }
    expect(syncs).to eq(3)

    5.times { adapter.chat(messages: [ { role: "user", content: "hi" } ], options: { agent_id: 1 }) }
    expect(syncs).to eq(3), "an open circuit must do nothing at all on this credential"
  end

  it "keeps serving a healthy credential on the same provider" do
    healthy_client = instance_double(Providers::Anthropic::SdkProxyClient)
    allow(healthy_client).to receive(:chat)
      .and_return(ServiceResponse.success(data: { content: "hello", usage: {} }))

    3.times { adapter.chat(messages: [ { role: "user", content: "hi" } ]) }

    allow(Providers::Anthropic::SdkProxyClient).to receive(:new).and_return(healthy_client)
    healthy = Providers::AnthropicAdapter.new(config: config, api_key: "sk-ant-oat01-funded")

    expect(healthy.chat(messages: [ { role: "user", content: "hi" } ])).to be_success
  end

  it "keeps retrying transient failures — the circuit is only for permanent ones" do
    allow(proxy_client).to receive(:chat).and_return(
      ServiceResponse.failure(
        error: "SDK proxy error (529): overloaded",
        payload: { provider_error: { message: "overloaded", status: 529,
                                     reason: "server_error", provider: "anthropic", retryable: true } }
      )
    )

    50.times { adapter.chat(messages: [ { role: "user", content: "hi" } ]) }

    expect(proxy_client).to have_received(:chat).exactly(50).times
  end

  it "recovers on the next call after a human tops the account up" do
    3.times { adapter.chat(messages: [ { role: "user", content: "hi" } ]) }
    expect(adapter.chat(messages: [ { role: "user", content: "hi" } ])).to be_failure

    Providers::CircuitBreaker.reset_provider!("anthropic")
    allow(proxy_client).to receive(:chat)
      .and_return(ServiceResponse.success(data: { content: "back", usage: {} }))

    expect(adapter.chat(messages: [ { role: "user", content: "hi" } ])).to be_success
  end

  describe "failover" do
    let(:agent) { nil }

    it "does not compound the churn: the chain is tried at most once per entry" do
      fallback = instance_double(Providers::OpenaiAdapter)
      allow(fallback).to receive(:chat).and_return(ServiceResponse.failure(
        error: "OpenAI API error (429): rate limited",
        payload: { provider_error: { reason: "rate_limited", retryable: true, status: 429 } }
      ))
      allow(Providers::Resolver).to receive(:call)
        .and_return(ServiceResponse.success(data: { adapter: fallback }))

      failover = Providers::FailoverAdapter.new(
        primary: adapter, chain: [ { provider: "openai", model: "gpt-4o" } ], agent: agent
      )
      failover.chat(messages: [ { role: "user", content: "hi" } ])

      expect(proxy_client).to have_received(:chat).once
      expect(fallback).to have_received(:chat).once
    end

    it "never fails over when the host is out of ephemeral ports" do
      allow(proxy_client).to receive(:chat).and_return(ServiceResponse.failure(
        error: "Failed to open TCP connection: Can't assign requested address",
        payload: { provider_error: { reason: "local_port_exhaustion", retryable: false, status: 503 } }
      ))
      fallback = instance_double(Providers::OpenaiAdapter)
      allow(fallback).to receive(:chat).and_return(ServiceResponse.success(data: { content: "x" }))
      allow(Providers::Resolver).to receive(:call)
        .and_return(ServiceResponse.success(data: { adapter: fallback }))

      failover = Providers::FailoverAdapter.new(
        primary: adapter, chain: [ { provider: "openai", model: "gpt-4o" } ], agent: agent
      )
      failover.chat(messages: [ { role: "user", content: "hi" } ])

      expect(fallback).not_to have_received(:chat),
                              "more attempts make port exhaustion worse, not better"
    end
  end
end
