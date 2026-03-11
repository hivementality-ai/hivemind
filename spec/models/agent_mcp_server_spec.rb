# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentMcpServer, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:agent) }
    it { is_expected.to belong_to(:mcp_server) }
  end

  describe "validations" do
    subject { create(:agent_mcp_server) }
    it { is_expected.to validate_uniqueness_of(:mcp_server_id).scoped_to(:agent_id) }
  end

  describe "creation" do
    it "links an agent to an MCP server" do
      assignment = create(:agent_mcp_server)
      expect(assignment.agent).to be_present
      expect(assignment.mcp_server).to be_present
    end
  end
end
