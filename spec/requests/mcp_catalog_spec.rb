# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP starter catalog", type: :request do
  let(:notion_url) { "https://mcp.notion.com/mcp" }

  describe "the catalog file" do
    let(:entries) { Mcp::Catalog.entries }

    it "lists the original remote servers and grows past twenty-five entries" do
      expect(entries.map(&:name)).to include("Notion", "Linear", "Atlassian", "Asana", "Stripe", "Sentry")
      expect(entries.size).to be >= 25
    end

    it "gives every entry a unique key, name, category, summary and https docs link" do
      expect(entries.map(&:key).uniq.size).to eq(entries.size)
      entries.each do |entry|
        expect(entry.key).to be_present
        expect(entry.name).to be_present
        expect(entry.category).to be_present
        expect(entry.summary).to be_present
        expect(entry.docs).to start_with("https://")
      end
    end

    it "gives every entry exactly one of a url or a command" do
      entries.each do |entry|
        expect([ entry.url.present?, entry.command.present? ].count(true)).to eq(1), "#{entry.key} needs exactly one of url or command"
      end
    end

    it "keeps remote entries on https without local fields" do
      entries.select(&:remote?).each do |entry|
        expect(entry.url).to start_with("https://")
        expect(entry.args).to be_nil
        expect(entry.inputs).to be_nil
      end
    end

    it "keeps every placeholder in a local entry's args backed by an arg input, and every arg input used" do
      entries.select(&:local?).each do |entry|
        placeholders = Array(entry.args).flat_map { |arg| arg.scan(/\{(\w+)\}/).flatten }
        arg_inputs = entry.input_list.select(&:arg?).map(&:key)
        expect(placeholders.sort).to eq(arg_inputs.sort), "#{entry.key} placeholders do not match its arg inputs"
      end
    end

    it "gives every input a key, a label and a known type" do
      entries.flat_map(&:input_list).each do |input|
        expect(input.key).to be_present
        expect(input.label).to be_present
        expect(%w[arg env secret]).to include(input.type)
      end
    end
  end

  describe "cards on the Integrations page" do
    before { sign_in create(:user, :owner) }

    it "shows an Add button for each server that is not added yet" do
      get integrations_path

      expect(response.body).to include("Search, read and update your Notion pages and databases.")
      expect(response.body).to include(add_from_catalog_mcp_servers_path(key: "notion"))
    end

    it "shows Connect for an added server that is not signed in" do
      server = create(:mcp_server, :sse, name: "Notion", url: notion_url)

      get integrations_path

      expect(response.body).to include(oauth_connect_mcp_server_path(server))
      expect(response.body).not_to include(add_from_catalog_mcp_servers_path(key: "notion"))
    end

    it "shows Connected for a server that is connected" do
      create(:mcp_server, :sse, :connected, name: "Notion", url: notion_url)

      get integrations_path

      expect(response.body).to match(%r{data-catalog="notion".*?Connected}m)
    end
  end

  describe "POST /mcp_servers/catalog/:key" do
    let(:meta) do
      { issuer: "https://auth.example.com", authorization_endpoint: "https://auth.example.com/authorize",
        token_endpoint: "https://auth.example.com/token", registration_endpoint: "https://auth.example.com/register" }
    end

    before do
      sign_in create(:user, :owner)
      stub_request(:post, notion_url).with { |r| JSON.parse(r.body)["method"] == "initialize" }
        .to_return(status: 401, headers: { "WWW-Authenticate" => 'Bearer resource_metadata="https://mcp.notion.com/prm"' })
      stub_request(:get, "https://mcp.notion.com/prm").to_return(body: { authorization_servers: [ "https://auth.example.com" ] }.to_json)
      stub_request(:get, "https://auth.example.com/.well-known/oauth-authorization-server").to_return(body: meta.to_json)
      stub_request(:post, meta[:registration_endpoint]).to_return(status: 201, body: { client_id: "cid" }.to_json)
    end

    it "creates the server and redirects into the OAuth flow" do
      expect { post add_from_catalog_mcp_servers_path(key: "notion") }.to change(McpServer, :count).by(1)

      expect(McpServer.last).to have_attributes(name: "Notion", url: notion_url, transport: "http")
      expect(response.location).to start_with("https://auth.example.com/authorize?")
    end

    it "assigns a newly added server to every visible agent so its tools reach them" do
      visible = create_list(:agent, 2)
      hidden = create(:agent, system_agent: true)

      post add_from_catalog_mcp_servers_path(key: "notion")
      server = McpServer.find_by!(name: "Notion")
      server.mark_connected!(tools: [ { "name" => "search", "description" => "Search" } ])

      expect(server.agents).to match_array(visible)
      expect(Mcp::ToolResolver.call(visible.first).data[:tools].map { |t| t[:name] }).to eq([ "mcp_notion_search" ])
      expect(Mcp::ToolResolver.call(hidden).data[:tools]).to be_empty
    end

    it "leaves an already added server's assignments alone" do
      agent = create(:agent)
      create(:mcp_server, :sse, name: "Notion", url: notion_url)

      post add_from_catalog_mcp_servers_path(key: "notion")

      expect(McpServer.find_by!(name: "Notion").agents).not_to include(agent)
    end

    it "reuses the server when it was already added" do
      create(:mcp_server, :sse, name: "Notion", url: notion_url)

      expect { post add_from_catalog_mcp_servers_path(key: "notion") }.not_to change(McpServer, :count)
      expect(response.location).to start_with("https://auth.example.com/authorize?")
    end

    it "adds under a free name when a different server already uses the name" do
      existing = create(:mcp_server, :sse, name: "Notion", url: "https://example.com/sse")
      create(:mcp_server, :sse, name: "Notion (catalog)", url: "https://example.com/other")

      expect { post add_from_catalog_mcp_servers_path(key: "notion") }.to change(McpServer, :count).by(1)

      expect(McpServer.find_by(name: "Notion (catalog) 2")).to have_attributes(url: notion_url)
      expect(existing.reload).to have_attributes(name: "Notion", url: "https://example.com/sse")
      expect(response.location).to start_with("https://auth.example.com/authorize?")
    end

    it "rejects a key that is not in the catalog" do
      expect { post add_from_catalog_mcp_servers_path(key: "nope") }.not_to change(McpServer, :count)
      expect(response).to redirect_to(integrations_path)
    end
  end

  describe "adding a local server" do
    let!(:agents) { create_list(:agent, 2) }

    before { sign_in create(:user, :owner) }

    def add(key, inputs = {})
      post add_from_catalog_mcp_servers_path(key: key), params: { inputs: inputs }
    end

    it "shows the form for an entry with inputs" do
      get catalog_form_mcp_servers_path(key: "filesystem")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Folder to share").and include('name="inputs[folder]"')
    end

    it "sends a remote or unknown key away from the form" do
      get catalog_form_mcp_servers_path(key: "notion")
      expect(response).to redirect_to(integrations_path)

      get catalog_form_mcp_servers_path(key: "nope")
      expect(response).to redirect_to(integrations_path)
    end

    it "fills an arg input into the stdio command and assigns every visible agent" do
      expect { add("filesystem", folder: "/workspace/my files") }.to change(McpServer, :count).by(1)

      server = McpServer.find_by!(name: "Files")
      expect(server).to have_attributes(transport: "stdio", command: "npx -y @modelcontextprotocol/server-filesystem /workspace/my\\ files")
      expect(server.metadata).to include("catalog_key" => "filesystem")
      expect(server.agents).to match_array(agents)
      expect(response).to redirect_to(mcp_servers_path)
    end

    it "keeps a secret input in the vault and only a reference on the row" do
      add("brave-search", BRAVE_API_KEY: "BSA-super-secret")

      server = McpServer.find_by!(name: "Brave Search")
      expect(server.env_vars).to eq("BRAVE_API_KEY" => "vault:mcp_brave_search/env_brave_api_key")
      expect(server.command).not_to include("BSA-super-secret")
      expect(server.resolved_env_vars).to eq("BRAVE_API_KEY" => "BSA-super-secret")
      expect(VaultEntry.find_by!(namespace: "mcp_brave_search", key: "env_brave_api_key").value).to eq("BSA-super-secret")
    end

    it "stores a plain env input as given and skips an optional one left blank" do
      add("resend", RESEND_API_KEY: "re_key", SENDER_EMAIL_ADDRESS: "")
      expect(McpServer.find_by!(name: "Resend").env_vars.keys).to eq([ "RESEND_API_KEY" ])

      add("grafana", GRAFANA_URL: "https://g.example.com", GRAFANA_SERVICE_ACCOUNT_TOKEN: "glsa_x")
      expect(McpServer.find_by!(name: "Grafana").env_vars).to include("GRAFANA_URL" => "https://g.example.com")
    end

    it "adds a local entry without inputs in one step" do
      expect { post add_from_catalog_mcp_servers_path(key: "time") }.to change(McpServer, :count).by(1)

      expect(McpServer.find_by!(name: "Time")).to have_attributes(command: "uvx mcp-server-time", env_vars: {})
    end

    it "re-renders with a plain error when a required input is missing" do
      expect { add("brave-search", BRAVE_API_KEY: "  ") }.not_to change(McpServer, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Brave Search API key is required.")
      expect(VaultEntry.where("namespace LIKE ?", "mcp_brave%")).to be_empty
    end

    it "never echoes a secret back into the re-rendered page" do
      add("grafana", GRAFANA_URL: "", GRAFANA_SERVICE_ACCOUNT_TOKEN: "glsa_do_not_echo")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Grafana address is required.")
      expect(response.body).not_to include("glsa_do_not_echo")
    end

    it "keeps the non-secret values the person already typed" do
      add("grafana", GRAFANA_URL: "https://g.example.com", GRAFANA_SERVICE_ACCOUNT_TOKEN: "")

      expect(response.body).to include("https://g.example.com")
    end

    it "refuses an arg input that starts with a dash so it cannot add a flag" do
      expect { add("filesystem", folder: "--read-only") }.not_to change(McpServer, :count)

      expect(response.body).to include("Folder to share cannot start with a dash.")
    end

    it "refuses a value with a line break" do
      expect { add("filesystem", folder: "/a\n/b") }.not_to change(McpServer, :count)

      expect(response.body).to include("Folder to share cannot contain a line break.")
    end

    it "does not add the same local entry twice" do
      add("time")

      expect { add("time") }.not_to change(McpServer, :count)
      expect(response).to redirect_to(mcp_servers_path)
    end

    it "adds under a free name when another server already uses the name" do
      create(:mcp_server, name: "Time")

      add("time")

      expect(McpServer.find_by(name: "Time (catalog)")).to have_attributes(command: "uvx mcp-server-time")
    end
  end

  describe "the shelf on the Integrations page" do
    before { sign_in create(:user, :owner) }

    it "groups the cards under a heading for each category" do
      get integrations_path

      Mcp::Catalog.categories.each do |category|
        expect(response.body).to include(%(data-category="#{category.parameterize}"))
        expect(response.body).to include(">#{ERB::Util.html_escape(category)}</h3>")
      end
    end

    it "wires the filter controller to its input, groups, cards and empty message" do
      get integrations_path
      card = Nokogiri::HTML(response.body).at_css("#mcp-catalog-card")

      expect(card["data-controller"]).to eq("catalog-filter")
      expect(card.at_css("input[data-catalog-filter-target='input'][data-action='input->catalog-filter#filter']")).to be_present
      expect(card.css("[data-catalog-filter-target='group']").size).to eq(Mcp::Catalog.categories.size)
      expect(card.css("[data-catalog-filter-target='item']").size).to eq(Mcp::Catalog.entries.size)
      expect(card.at_css("[data-catalog-filter-target='empty']")).to be_present
    end

    it "makes each card searchable by name, summary and category" do
      get integrations_path
      item = Nokogiri::HTML(response.body).at_css("[data-catalog='brave-search']")

      expect(item["data-search-text"]).to include("brave search", "web")
    end

    it "opens the form for an entry with inputs instead of a one-click add" do
      get integrations_path

      html = Nokogiri::HTML(response.body)
      with_inputs = html.at_css("[data-catalog='brave-search']")
      without_inputs = html.at_css("[data-catalog='time']")

      expect(with_inputs.at_css("a[href='#{catalog_form_mcp_servers_path(key: 'brave-search')}']")).to be_present
      expect(with_inputs.at_css("form")).to be_nil
      expect(without_inputs.at_css("form[action='#{add_from_catalog_mcp_servers_path(key: 'time')}']")).to be_present
    end

    it "marks an added local entry and offers no second add" do
      create(:mcp_server, name: "Time", command: "uvx mcp-server-time", metadata: { "catalog_key" => "time" })

      get integrations_path

      item = Nokogiri::HTML(response.body).at_css("[data-catalog='time']")
      expect(item.at_css("form")).to be_nil
      expect(item.text).to include("Added")
    end

    it "keeps tap targets at 44px and cards from forcing horizontal scroll" do
      get integrations_path
      html = Nokogiri::HTML(response.body)
      card = html.at_css("[data-catalog='brave-search']")

      expect(card["class"]).to include("min-w-0")
      expect(card.css("a, button, input[type=submit]").map { |el| el["class"] }).to all(include("min-h-[44px]"))
      expect(html.at_css("input[name='catalog_search']")["class"]).to include("min-h-[44px]")
    end
  end
end
