# frozen_string_literal: true

# A chunk of an ingested document with its embedding vector. Mirrors the
# pgvector setup of MemoryEntry (768-dim cosine, has_neighbors).
class KnowledgeChunk < ApplicationRecord
  belongs_to :knowledge_document
  belongs_to :agent

  has_neighbors :embedding

  validates :content, presence: true

  scope :for_agent, ->(agent) { where(agent: agent) }

  # Semantic search over chunks using pgvector cosine similarity.
  # Scoped to an agent and to chunks of ready documents.
  def self.search_similar(embedding:, agent:, limit: 5)
    where(agent: agent)
      .where(knowledge_document_id: KnowledgeDocument.ready.select(:id))
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .limit(limit)
  end

  def embedded?
    embedding.present?
  end
end
