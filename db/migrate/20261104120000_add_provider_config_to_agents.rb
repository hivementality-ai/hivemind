# frozen_string_literal: true

# Lets an agent pin the specific ProviderConfig it runs on, so two providers
# sharing an adapter type can coexist. Existing agents are pinned to the first
# enabled config of their current adapter type, which is what the by-type
# lookup already resolved to.
class AddProviderConfigToAgents < ActiveRecord::Migration[8.1]
  def up
    add_reference :agents, :provider_config, null: true, foreign_key: { on_delete: :nullify }

    execute <<~SQL.squish
      UPDATE agents
      SET provider_config_id = (
        SELECT provider_configs.id FROM provider_configs
        WHERE provider_configs.adapter_type = agents.model_provider
          AND provider_configs.enabled = TRUE
        ORDER BY provider_configs.id
        LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :agents, :provider_config, foreign_key: true
  end
end
