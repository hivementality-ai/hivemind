# frozen_string_literal: true

# Document-ingestion knowledge base (RAG). Reuses the pgvector setup and the
# 768-dim embedding column convention established by memory_entries.
class CreateKnowledgeBase < ActiveRecord::Migration[8.0]
  def change
    create_table :knowledge_documents do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :title, null: false
      t.string :source_type, null: false, default: "text" # text | pdf
      t.string :source_url
      t.string :status, null: false, default: "pending"   # pending | processing | ready | failed
      t.text :error
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :knowledge_documents, [ :agent_id, :status ]

    create_table :knowledge_chunks do |t|
      t.references :knowledge_document, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true # denormalized from document for scoped search
      t.text :content, null: false
      t.integer :position, null: false, default: 0
      t.vector :embedding, limit: 768 # same dims as memory_entries
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    # HNSW cosine index, mirroring index_memory_entries_on_embedding
    add_index :knowledge_chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops,
                                             name: "index_knowledge_chunks_on_embedding"
    add_index :knowledge_chunks, [ :agent_id, :knowledge_document_id ]
  end
end
