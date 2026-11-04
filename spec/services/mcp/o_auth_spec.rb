# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::OAuth do
  let(:url) { "https://mcp.example.com/mcp" }
  let(:server) { create(:mcp_server, :sse, url: url) }
  let(:redirect_uri) { "https://hive.example.com/mcp_servers/#{server.id}/oauth_callback" }
  let(:prm_url) { "https://mcp.example.com/.well-known/oauth-protected-resource/mcp" }
  let(:as_url) { "https://auth.example.com/.well-known/oauth-authorization-server" }
  let(:as_meta) do
    { issuer: "https://auth.example.com", authorization_endpoint: "https://auth.example.com/authorize",
      token_endpoint: "https://auth.example.com/token", registration_endpoint: "https://auth.example.com/register" }
  end

  def stub_discovery(challenge: %(Bearer resource_metadata="#{prm_url}", scope="read write"))
    stub_request(:post, url).to_return(status: 401, headers: { "WWW-Authenticate" => challenge })
    stub_request(:get, prm_url).to_return(status: 200, body: { resource: url, authorization_servers: [ "https://auth.example.com" ] }.to_json)
    stub_request(:get, as_url).to_return(status: 200, body: as_meta.to_json)
  end

  def stub_registration
    stub_request(:post, as_meta[:registration_endpoint])
      .to_return(status: 201, body: { client_id: "client-1" }.to_json)
  end

  def stub_token(body = { access_token: "at-1", refresh_token: "rt-1", expires_in: 3600 })
    stub_request(:post, as_meta[:token_endpoint]).to_return(status: 200, body: body.to_json)
  end

  def vault_json(key)
    JSON.parse(VaultEntry.find_by!(namespace: "mcp_oauth_#{server.id}", key: key).value)
  end

  def authorize_params(auth_url)
    Rack::Utils.parse_query(URI.parse(auth_url).query)
  end

  describe ".authorization_url" do
    before do
      stub_discovery
      stub_registration
    end

    it "discovers the authorization server from the 401 challenge and builds a PKCE URL" do
      auth_url = described_class.authorization_url(server, redirect_uri: redirect_uri)
      params = authorize_params(auth_url)

      expect(auth_url).to start_with("https://auth.example.com/authorize?")
      expect(params).to include("response_type" => "code", "client_id" => "client-1", "redirect_uri" => redirect_uri,
                                "code_challenge_method" => "S256", "resource" => url, "scope" => "read write")
      expect(params["state"]).to eq(vault_json("pending")["state"])
    end

    it "sends an S256 challenge derived from the stored verifier and never exposes the verifier" do
      auth_url = described_class.authorization_url(server, redirect_uri: redirect_uri)
      verifier = vault_json("pending")["verifier"]

      expect(authorize_params(auth_url)["code_challenge"]).to eq(Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false))
      expect(auth_url).not_to include(verifier)
    end

    it "registers a public client dynamically and reuses it for the same redirect" do
      described_class.authorization_url(server, redirect_uri: redirect_uri)
      described_class.authorization_url(server, redirect_uri: redirect_uri)

      expect(WebMock).to have_requested(:post, as_meta[:registration_endpoint]).once
      expect(WebMock).to have_requested(:post, as_meta[:registration_endpoint]).with { |req|
        body = JSON.parse(req.body)
        body["redirect_uris"] == [ redirect_uri ] && body["token_endpoint_auth_method"] == "none"
      }
    end

    it "falls back to well-known protected resource metadata when the 401 has no pointer" do
      stub_discovery(challenge: "Bearer")

      expect(described_class.authorization_url(server, redirect_uri: redirect_uri)).to start_with("https://auth.example.com/authorize")
    end

    it "falls back to OIDC discovery when RFC 8414 metadata is absent" do
      stub_request(:get, as_url).to_return(status: 404)
      stub_request(:get, "https://auth.example.com/.well-known/openid-configuration").to_return(status: 200, body: as_meta.to_json)

      expect(described_class.authorization_url(server, redirect_uri: redirect_uri)).to start_with("https://auth.example.com/authorize")
    end

    it "fails when the server offers no dynamic registration" do
      stub_request(:get, as_url).to_return(status: 200, body: as_meta.except(:registration_endpoint).to_json)

      expect { described_class.authorization_url(server, redirect_uri: redirect_uri) }
        .to raise_error(described_class::Error, /dynamic client registration/)
    end

    it "works against plain-http localhost and LAN servers" do
      lan = create(:mcp_server, :sse, url: "http://192.168.1.20:8080/mcp")
      stub_request(:post, "http://192.168.1.20:8080/mcp").to_return(status: 401, headers: { "WWW-Authenticate" => "Bearer" })
      stub_request(:get, "http://192.168.1.20:8080/.well-known/oauth-protected-resource/mcp")
        .to_return(status: 200, body: { authorization_servers: [ "http://localhost:9000" ] }.to_json)
      stub_request(:get, "http://localhost:9000/.well-known/oauth-authorization-server")
        .to_return(status: 200, body: as_meta.merge(authorization_endpoint: "http://localhost:9000/authorize").to_json)
      stub_registration

      expect(described_class.authorization_url(lan, redirect_uri: "http://localhost:3000/cb")).to start_with("http://localhost:9000/authorize")
    end

    it "refuses plain-http metadata from a public host" do
      stub_request(:get, prm_url).to_return(status: 200, body: { authorization_servers: [ "http://auth.example.com" ] }.to_json)

      expect { described_class.authorization_url(server, redirect_uri: redirect_uri) }
        .to raise_error(described_class::Error, /authorization server metadata/)
    end

    it "refuses a plain-http token endpoint on a public host" do
      stub_request(:get, as_url).to_return(status: 200, body: as_meta.merge(token_endpoint: "http://auth.example.com/token").to_json)

      expect { described_class.authorization_url(server, redirect_uri: redirect_uri) }
        .to raise_error(described_class::Error, /must use https/)
    end
  end

  describe ".complete!" do
    let(:state) { authorize_params(described_class.authorization_url(server, redirect_uri: redirect_uri))["state"] }

    before do
      stub_discovery
      stub_registration
    end

    it "exchanges the code with the PKCE verifier and stores tokens only in the vault" do
      stub_token
      verifier_state = state
      verifier = vault_json("pending")["verifier"]

      described_class.complete!(server, code: "code-1", state: verifier_state)

      expect(WebMock).to have_requested(:post, as_meta[:token_endpoint]).with { |req|
        form = Rack::Utils.parse_query(req.body)
        form.values_at("grant_type", "code", "code_verifier", "client_id", "resource", "redirect_uri") ==
          [ "authorization_code", "code-1", verifier, "client-1", url, redirect_uri ]
      }
      expect(vault_json("tokens")).to include("access_token" => "at-1", "refresh_token" => "rt-1")
      expect(VaultEntry.connection.select_values("SELECT encrypted_value FROM vault_entries").join).not_to include("at-1")
      expect(server.reload.attributes.values.join).not_to include("at-1")
    end

    it "rejects a bad state without calling the token endpoint" do
      token = stub_token
      state

      expect { described_class.complete!(server, code: "c", state: "forged") }.to raise_error(described_class::Error, /Invalid state/)
      expect(token).not_to have_been_requested
    end

    it "makes state single use" do
      stub_token
      good = state
      described_class.complete!(server, code: "c", state: good)

      expect { described_class.complete!(server, code: "c", state: good) }.to raise_error(described_class::Error, /No authorization is pending/)
    end

    it "burns the pending state on a failed attempt" do
      good = state
      expect { described_class.complete!(server, code: "c", state: "forged") }.to raise_error(described_class::Error)

      expect { described_class.complete!(server, code: "c", state: good) }.to raise_error(described_class::Error, /No authorization is pending/)
    end

    it "rejects an expired state" do
      stub_token
      good = state

      travel_to(described_class::STATE_TTL.from_now + 1.second) do
        expect { described_class.complete!(server, code: "c", state: good) }.to raise_error(described_class::Error, /expired/)
      end
    end

    it "surfaces a token endpoint failure" do
      stub_request(:post, as_meta[:token_endpoint]).to_return(status: 400, body: "{}")

      expect { described_class.complete!(server, code: "c", state: state) }.to raise_error(described_class::Error, /Token request failed/)
    end
  end

  describe "tokens" do
    before do
      stub_discovery
      stub_registration
      stub_token
      described_class.complete!(server, code: "c", state: authorize_params(described_class.authorization_url(server, redirect_uri: redirect_uri))["state"])
    end

    it "builds a bearer header from the stored token" do
      expect(described_class.headers_for(server)).to eq("Authorization" => "Bearer at-1")
      expect(described_class).to be_connected(server)
    end

    it "refreshes an expired token before handing out a header and keeps the old refresh token if none is rotated" do
      refresh = stub_request(:post, as_meta[:token_endpoint]).with { |req| req.body.include?("grant_type=refresh_token") }
        .to_return(status: 200, body: { access_token: "at-2", expires_in: 60 }.to_json)

      travel_to(2.hours.from_now) do
        expect(described_class.headers_for(server)).to eq("Authorization" => "Bearer at-2")
      end
      expect(refresh).to have_been_requested.once
      expect(vault_json("tokens")).to include("access_token" => "at-2", "refresh_token" => "rt-1")
    end

    it "returns no header for a server that never connected" do
      expect(described_class.headers_for(create(:mcp_server, :sse))).to eq({})
    end
  end
end
