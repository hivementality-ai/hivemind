# frozen_string_literal: true

class VaultEntry < ApplicationRecord
  belongs_to :agent, optional: true # nil = global scope

  encrypts :encrypted_value

  # Convenience alias
  alias_attribute :value, :encrypted_value

  validates :namespace, presence: true
  validates :key, presence: true
  validates :key, uniqueness: { scope: %i[agent_id namespace] }

  scope :global, -> { where(agent_id: nil) }
  scope :for_agent, ->(agent) { where(agent_id: [ agent.id, nil ]) }
  scope :in_namespace, ->(ns) { where(namespace: ns) }

  def self.resolve(namespace:, key:, agent: nil)
    # Agent-scoped takes priority, then global
    entry = find_by(namespace:, key:, agent_id: agent&.id)
    entry || find_by(namespace:, key:, agent_id: nil)
  end
end
