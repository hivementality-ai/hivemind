# frozen_string_literal: true

class ConvertEmbeddingToVector < ActiveRecord::Migration[8.0]
  def up
    enable_extension 'vector'

    # Remove old JSONB column
    remove_column :memory_entries, :embedding

    # Add proper pgvector column
    add_column :memory_entries, :embedding, :vector, limit: 1536

    # Add HNSW index for fast similarity search
    add_index :memory_entries, :embedding, using: :hnsw, opclass: :vector_cosine_ops, name: "index_memory_entries_on_embedding"
  end

  def down
    remove_index :memory_entries, name: "index_memory_entries_on_embedding"
    remove_column :memory_entries, :embedding
    add_column :memory_entries, :embedding, :jsonb, null: false, default: []
  end
end
