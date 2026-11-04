# frozen_string_literal: true

# A connector hidden from one agent. Agents see every enabled connector unless a row says otherwise.
class AgentConnectorExclusion < ApplicationRecord
  belongs_to :agent
  belongs_to :connector

  validates :connector_id, uniqueness: { scope: :agent_id }
end
