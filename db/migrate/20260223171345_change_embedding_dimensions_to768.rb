# frozen_string_literal: true

class ChangeEmbeddingDimensionsTo768 < ActiveRecord::Migration[8.0]
  def up
    # Remove old HNSW index
    remove_index :memory_entries, name: "index_memory_entries_on_embedding"

    # Clear existing embeddings (dimension change makes old ones incompatible)
    execute "UPDATE memory_entries SET embedding = NULL"

    # Change column to 768 dimensions (nomic-embed-text native output)
    remove_column :memory_entries, :embedding
    add_column :memory_entries, :embedding, :vector, limit: 768

    # Re-add HNSW index
    add_index :memory_entries, :embedding, using: :hnsw, opclass: :vector_cosine_ops, name: "index_memory_entries_on_embedding"
  end

  def down
    remove_index :memory_entries, name: "index_memory_entries_on_embedding"
    remove_column :memory_entries, :embedding
    add_column :memory_entries, :embedding, :vector, limit: 1536
    add_index :memory_entries, :embedding, using: :hnsw, opclass: :vector_cosine_ops, name: "index_memory_entries_on_embedding"
  end
end
