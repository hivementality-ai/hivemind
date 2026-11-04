# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteAccessHealthCheckJob, type: :job do
  after { RemoteAccess::ConfigStore.clear! }

  it "does nothing when remote access is not configured" do
    expect(RemoteAccess::HealthCheck).not_to receive(:call)
    described_class.new.perform
  end

  it "re-checks the canonical host and records the result when configured" do
    RemoteAccess::ConfigStore.canonical_host = "https://hivemind.example.com"
    RemoteAccess::ConfigStore.mode = "byo"

    allow(RemoteAccess::HealthCheck).to receive(:call)
      .with("https://hivemind.example.com")
      .and_return(ServiceResponse.success(data: { http: { ok: true, status: 200 }, websocket: { ok: true } }))

    described_class.new.perform

    expect(RemoteAccess::ConfigStore.http_ok?).to eq(true)
    expect(RemoteAccess::ConfigStore.websocket_ok?).to eq(true)
  end

  it "records a failed check without raising" do
    RemoteAccess::ConfigStore.canonical_host = "https://hivemind.example.com"
    RemoteAccess::ConfigStore.mode = "byo"

    allow(RemoteAccess::HealthCheck).to receive(:call)
      .and_return(ServiceResponse.failure(error: "unreachable", payload: { http: { ok: false }, websocket: { ok: false } }))

    expect { described_class.new.perform }.not_to raise_error
    expect(RemoteAccess::ConfigStore.http_ok?).to eq(false)
    expect(RemoteAccess::ConfigStore.last_error).to eq("unreachable")
  end
end
