# frozen_string_literal: true

class EnablePgvectorAndCreateMemoryEntries < ActiveRecord::Migration[8.0]
  def change
    # Enable pgvector extension if available
    # Run: brew install pgvector (Mac) or install postgresql-XX-pgvector package (Linux)
    # Then: CREATE EXTENSION vector; in PostgreSQL
    # For now, we'll use text/jsonb for embedding storage

    create_table :memory_entries do |t|
      t.references :agent, null: false, foreign_key: true
      t.text :content, null: false
      t.jsonb :embedding, null: false, default: []  # Store as JSON array for now
      t.string :source_type
      t.bigint :source_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :memory_entries, [ :source_type, :source_id ]

    # When pgvector is installed, run this migration to add vector support:
    # ALTER TABLE memory_entries ADD COLUMN embedding_vector vector(1536);
    # CREATE INDEX ON memory_entries USING ivfflat (embedding_vector vector_cosine_ops);
  end
end
