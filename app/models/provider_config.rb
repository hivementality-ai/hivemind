# frozen_string_literal: true

class ProviderConfig < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :adapter_type, presence: true, inclusion: { in: %w[openai anthropic ollama] }

  scope :enabled_providers, -> { where(enabled: true) }

  after_initialize :set_defaults

  def api_key(agent: nil)
    return nil if vault_key.blank?

    namespace, key = vault_key.split("/", 2)
    entry = VaultEntry.resolve(namespace:, key:, agent:)
    entry&.encrypted_value
  end

  private

  def set_defaults
    self.model_definitions ||= []
    self.enabled = true if enabled.nil?
  end
end
