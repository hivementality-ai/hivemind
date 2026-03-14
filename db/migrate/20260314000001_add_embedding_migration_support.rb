# frozen_string_literal: true

class AddEmbeddingMigrationSupport < ActiveRecord::Migration[8.0]
  def change
    # Shadow column for dual-write during provider migration
    add_column :memory_entries, :shadow_embedding, :vector, limit: 768

    # Track which provider/model created each embedding
    add_column :memory_entries, :embedding_provider, :string
    add_column :memory_entries, :embedding_model, :string

    add_index :memory_entries, :shadow_embedding,
      using: :hnsw,
      opclass: :vector_cosine_ops,
      name: "index_memory_entries_on_shadow_embedding"

    # Migration status tracking
    create_table :embedding_migration_statuses do |t|
      t.string :from_provider, null: false
      t.string :to_provider, null: false
      t.string :phase, default: "shadow", null: false
      t.datetime :started_at
      t.datetime :validated_at
      t.datetime :completed_at
      t.datetime :rolled_back_at
      t.jsonb :validation_results, default: {}

      t.timestamps
    end
  end
end
