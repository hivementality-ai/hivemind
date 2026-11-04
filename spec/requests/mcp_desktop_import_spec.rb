# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Claude Desktop import", type: :request do
  let(:secret) { "ghp_supersecret_123456" }
  let(:config_json) do
    { mcpServers: {
      "github" => { command: "npx", args: [ "-y", "@modelcontextprotocol/server-github" ], env: { "GITHUB_TOKEN" => secret, "GITHUB_HOST" => "github.com" } },
      "remote" => { url: "https://mcp.example.com/mcp", headers: { "Authorization" => "Bearer #{secret}" } },
      "ignored" => { command: "echo" }
    } }.to_json
  end

  before { sign_in create(:user, :owner) }

  def token_from(body)
    Nokogiri::HTML(body).at_css("input[name=token]")["value"]
  end

  it "previews the entries without echoing any env or header value" do
    post preview_mcp_import_path, params: { config_json: config_json }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("github", "remote", "GITHUB_TOKEN", "https://mcp.example.com/mcp")
    expect(response.body).not_to include(secret)
    expect(response.body).not_to include("github.com\"")
  end

  it "rejects text that has no mcpServers" do
    post preview_mcp_import_path, params: { config_json: "{}" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("No mcpServers found")
  end

  it "imports only the ticked servers, moving env and header values into the vault" do
    post preview_mcp_import_path, params: { config_json: config_json }
    post mcp_import_path, params: { token: token_from(response.body), names: %w[github remote] }

    expect(response).to redirect_to(mcp_servers_path)
    expect(response.body).not_to include(secret)
    expect(McpServer.pluck(:name)).to contain_exactly("github", "remote")

    github = McpServer.find_by(name: "github")
    expect(github).to have_attributes(transport: "stdio", command: "npx -y @modelcontextprotocol/server-github")
    expect(github.env_vars).to eq("GITHUB_TOKEN" => "vault:mcp_import_github/env_github_token",
                                  "GITHUB_HOST" => "vault:mcp_import_github/env_github_host")
    expect(VaultEntry.find_by(namespace: "mcp_import_github", key: "env_github_token").value).to eq(secret)
    expect(github.to_json).not_to include(secret)

    remote = McpServer.find_by(name: "remote")
    expect(remote).to have_attributes(transport: "http", url: "https://mcp.example.com/mcp")
    expect(remote.auth_config).to eq("Authorization" => "vault:mcp_import_remote/auth_authorization")
    expect(remote.resolved_auth_headers["Authorization"]).to eq("Bearer #{secret}")
  end

  it "assigns imported servers to every visible agent" do
    agent = create(:agent)
    post preview_mcp_import_path, params: { config_json: config_json }
    post mcp_import_path, params: { token: token_from(response.body), names: %w[github] }

    expect(McpServer.find_by!(name: "github").agents).to eq([ agent ])
  end

  it "skips a server whose name is already taken" do
    create(:mcp_server, name: "github")
    post preview_mcp_import_path, params: { config_json: config_json }
    post mcp_import_path, params: { token: token_from(response.body), names: %w[github] }

    expect(McpServer.where(name: "github").count).to eq(1)
    expect(VaultEntry.where(namespace: "mcp_import_github")).to be_empty
  end

  it "refuses a forged token" do
    post mcp_import_path, params: { token: "nope", names: %w[github] }

    expect(response).to redirect_to(new_mcp_import_path)
    expect(McpServer.count).to eq(0)
  end
end
