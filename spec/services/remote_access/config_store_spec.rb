# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteAccess::ConfigStore, type: :service do
  after { described_class.clear! }

  it "is unconfigured by default" do
    expect(described_class.configured?).to eq(false)
  end

  it "is configured once both a host and mode are set" do
    described_class.canonical_host = "https://hivemind.example.com"
    described_class.mode = "byo"
    expect(described_class.configured?).to eq(true)
  end

  it "rejects an invalid mode" do
    expect { described_class.mode = "carrier_pigeon" }.to raise_error(ArgumentError)
  end

  it "stores Cloudflare secrets encrypted via VaultEntry, not in Setting" do
    described_class.cloudflare_api_token = "cf-secret-token"

    expect(described_class.cloudflare_api_token).to eq("cf-secret-token")
    expect(Setting.get("cloudflare_api_token")).to be_nil
    entry = VaultEntry.find_by(namespace: "remote_access", key: "cloudflare_api_token")
    expect(entry).to be_present
    expect(entry.encrypted_value).to eq("cf-secret-token")
  end

  it "records and reports check results" do
    described_class.record_check_result(http_ok: true, websocket_ok: false, error: "cable unreachable")

    expect(described_class.http_ok?).to eq(true)
    expect(described_class.websocket_ok?).to eq(false)
    expect(described_class.last_error).to eq("cable unreachable")
    expect(described_class.last_check_at).to be_within(5.seconds).of(Time.current)
  end

  it "clears all settings and vault entries" do
    described_class.canonical_host = "https://hivemind.example.com"
    described_class.mode = "cloudflare"
    described_class.cloudflare_tunnel_token = "tok"
    described_class.cloudflare_tunnel_id = "tun_1"

    described_class.clear!

    expect(described_class.canonical_host).to be_nil
    expect(described_class.mode).to be_blank
    expect(described_class.cloudflare_tunnel_token).to be_nil
    expect(described_class.cloudflare_tunnel_id).to be_nil
  end
end
