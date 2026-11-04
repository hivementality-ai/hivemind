# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cloudflare::TunnelProvisioner, type: :service do
  let(:api_token) { "cf-token-123" }
  let(:hostname) { "hivemind.example.com" }
  let(:provisioner) { described_class.new(api_token: api_token, internal_port: 3000) }

  describe ".token_deep_link" do
    it "links to the Cloudflare dashboard token creation page" do
      expect(described_class.token_deep_link).to start_with("https://dash.cloudflare.com/profile/api-tokens")
    end
  end

  describe "#provision" do
    it "requires a hostname" do
      result = provisioner.provision(hostname: "")
      expect(result).not_to be_success
      expect(result.error).to include("Hostname")
    end

    context "happy path" do
      before do
        stub_request(:get, "https://api.cloudflare.com/client/v4/accounts")
          .with(headers: { "Authorization" => "Bearer #{api_token}" })
          .to_return(status: 200, body: { success: true, result: [ { "id" => "acct123" } ] }.to_json)

        stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
          .with(query: { "name" => "hivemind.example.com" })
          .to_return(status: 200, body: { success: true, result: [] }.to_json)

        stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
          .with(query: { "name" => "example.com" })
          .to_return(status: 200, body: { success: true, result: [ { "id" => "zone123", "name" => "example.com" } ] }.to_json)

        stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/acct123/cfd_tunnel")
          .to_return(status: 200, body: {
            success: true,
            result: { "id" => "tunnel123", "token" => "run-token-abc" }
          }.to_json)

        stub_request(:put, "https://api.cloudflare.com/client/v4/accounts/acct123/cfd_tunnel/tunnel123/configurations")
          .to_return(status: 200, body: { success: true }.to_json)

        stub_request(:post, "https://api.cloudflare.com/client/v4/zones/zone123/dns_records")
          .to_return(status: 200, body: { success: true, result: { "id" => "dns123" } }.to_json)
      end

      it "creates the tunnel, configures ingress, creates the DNS record, and returns the run token" do
        result = provisioner.provision(hostname: hostname)

        expect(result).to be_success
        expect(result.data[:tunnel_id]).to eq("tunnel123")
        expect(result.data[:tunnel_token]).to eq("run-token-abc")
        expect(result.data[:account_id]).to eq("acct123")
        expect(result.data[:zone_id]).to eq("zone123")
        expect(result.data[:public_url]).to eq("https://hivemind.example.com")

        expect(WebMock).to have_requested(:put, "https://api.cloudflare.com/client/v4/accounts/acct123/cfd_tunnel/tunnel123/configurations")
          .with(body: hash_including(
            "config" => hash_including(
              "ingress" => array_including(hash_including("hostname" => hostname, "service" => "http://app:3000"))
            )
          ))

        expect(WebMock).to have_requested(:post, "https://api.cloudflare.com/client/v4/zones/zone123/dns_records")
          .with(body: hash_including("type" => "CNAME", "content" => "tunnel123.cfargotunnel.com"))
      end
    end

    context "when no Cloudflare account is found" do
      it "fails without calling the tunnel-creation endpoint" do
        stub_request(:get, "https://api.cloudflare.com/client/v4/accounts")
          .to_return(status: 200, body: { success: true, result: [] }.to_json)

        result = provisioner.provision(hostname: hostname)

        expect(result).not_to be_success
        expect(result.error).to include("account")
      end
    end

    context "when no zone matches the hostname" do
      it "fails with a helpful message" do
        stub_request(:get, "https://api.cloudflare.com/client/v4/accounts")
          .to_return(status: 200, body: { success: true, result: [ { "id" => "acct123" } ] }.to_json)

        stub_request(:get, %r{\Ahttps://api\.cloudflare\.com/client/v4/zones})
          .to_return(status: 200, body: { success: true, result: [] }.to_json)

        result = provisioner.provision(hostname: hostname)

        expect(result).not_to be_success
        expect(result.error).to include("No Cloudflare zone found")
      end
    end

    context "when tunnel creation fails" do
      it "surfaces the Cloudflare API error" do
        stub_request(:get, "https://api.cloudflare.com/client/v4/accounts")
          .to_return(status: 200, body: { success: true, result: [ { "id" => "acct123" } ] }.to_json)

        stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
          .with(query: { "name" => "hivemind.example.com" })
          .to_return(status: 200, body: { success: true, result: [] }.to_json)

        stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
          .with(query: { "name" => "example.com" })
          .to_return(status: 200, body: { success: true, result: [ { "id" => "zone123", "name" => "example.com" } ] }.to_json)

        stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/acct123/cfd_tunnel")
          .to_return(status: 403, body: { success: false, errors: [ { "code" => 9109, "message" => "Invalid access token" } ] }.to_json)

        result = provisioner.provision(hostname: hostname)

        expect(result).not_to be_success
        expect(result.error).to include("Invalid access token")
      end
    end

    context "when the DNS record already exists" do
      it "treats it as success (idempotent re-provisioning)" do
        stub_request(:get, "https://api.cloudflare.com/client/v4/accounts")
          .to_return(status: 200, body: { success: true, result: [ { "id" => "acct123" } ] }.to_json)

        stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
          .with(query: { "name" => "hivemind.example.com" })
          .to_return(status: 200, body: { success: true, result: [] }.to_json)

        stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
          .with(query: { "name" => "example.com" })
          .to_return(status: 200, body: { success: true, result: [ { "id" => "zone123", "name" => "example.com" } ] }.to_json)

        stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/acct123/cfd_tunnel")
          .to_return(status: 200, body: { success: true, result: { "id" => "tunnel123", "token" => "run-token-abc" } }.to_json)

        stub_request(:put, "https://api.cloudflare.com/client/v4/accounts/acct123/cfd_tunnel/tunnel123/configurations")
          .to_return(status: 200, body: { success: true }.to_json)

        stub_request(:post, "https://api.cloudflare.com/client/v4/zones/zone123/dns_records")
          .to_return(status: 400, body: { success: false, errors: [ { "code" => 81_053, "message" => "Record already exists" } ] }.to_json)

        result = provisioner.provision(hostname: hostname)
        expect(result).to be_success
      end
    end
  end
end
