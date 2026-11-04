# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidebar navigation", type: :request do
  before { sign_in create(:user, :owner) }

  it "keeps every link in the sidebar" do
    get agents_path

    [ providers_path, integrations_path, mcp_servers_path, remote_access_path, channels_path,
      agent_templates_path, budgets_path, knowledge_documents_path, approvals_path, audit_logs_path,
      api_integrations_path, api_tokens_path, webhook_endpoints_path, migration_path,
      platform_status_path, platform_doctor_path ].each do |path|
      expect(response.body).to include(%(href="#{path}")), "missing nav link #{path}"
    end
  end

  it "groups the developer links under Advanced, not Configuration" do
    get agents_path

    advanced = response.body[/data-nav-group-name-value="advanced".*/m]
    configuration = response.body[/data-nav-group-name-value="configuration".*?data-nav-group-name-value="advanced"/m]

    [ api_integrations_path, api_tokens_path, webhook_endpoints_path, migration_path,
      platform_status_path, platform_doctor_path ].each do |path|
      expect(advanced).to include(%(href="#{path}"))
      expect(configuration).not_to include(%(href="#{path}"))
    end
  end
end
