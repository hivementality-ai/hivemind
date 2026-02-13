# frozen_string_literal: true

class CreateApiIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :api_integrations do |t|
      t.string :name, null: false
      t.string :base_url, null: false
      t.text :description
      t.string :spec_format, default: "openapi"       # openapi, swagger, custom
      t.jsonb :spec_data, default: {}                  # Full parsed spec
      t.jsonb :auth_config, default: {}                # Auth type, header name, etc.
      t.jsonb :default_headers, default: {}            # Headers to send with every request
      t.jsonb :endpoints, default: []                  # Parsed endpoint summaries for LLM
      t.boolean :enabled, default: true
      t.integer :timeout_seconds, default: 30
      t.integer :max_response_bytes, default: 1_048_576 # 1MB
      t.references :user, foreign_key: true            # Who created it
      t.timestamps
    end

    add_index :api_integrations, :name, unique: true
    add_index :api_integrations, :enabled
  end
end
