# frozen_string_literal: true

# Per-operation failure tracking so a connector can notice its own definition has gone stale.
class AddHealthToConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :connectors, :health, :jsonb, default: {}, null: false
  end
end
