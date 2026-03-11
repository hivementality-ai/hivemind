# frozen_string_literal: true

class AgentMcpServer < ApplicationRecord
  belongs_to :agent
  belongs_to :mcp_server

  validates :mcp_server_id, uniqueness: { scope: :agent_id }
end
