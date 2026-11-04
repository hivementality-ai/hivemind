# frozen_string_literal: true

# A connector describes an HTTP API as data: base URL, auth scheme (secrets held
# only as vault references) and a list of operations exposed to agents as tools.
class CreateConnectors < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :base_url, null: false
      t.string :auth_scheme, null: false, default: "none"
      t.jsonb :auth_config, null: false, default: {}
      t.jsonb :operations, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.string :created_by_type
      t.bigint :created_by_id

      t.timestamps
    end

    add_index :connectors, :slug, unique: true
    add_index :connectors, :enabled
    add_index :connectors, %i[created_by_type created_by_id]
  end
end
