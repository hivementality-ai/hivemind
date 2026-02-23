# frozen_string_literal: true

class MemoryEntry < ApplicationRecord
  belongs_to :agent
  belongs_to :source, polymorphic: true, optional: true

  has_neighbors :embedding

  validates :content, presence: true

  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :by_source_type, ->(type) { where(source_type: type) }

  # Search for similar memories using pgvector cosine similarity
  def self.search_similar(embedding:, agent:, limit: 10)
    where(agent: agent)
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .limit(limit)
  end

  # Search with a minimum similarity threshold (0-1, where 1 is identical)
  # neighbor_distance is cosine distance (0 = identical, 2 = opposite)
  # threshold is similarity (1 = identical, 0 = unrelated)
  def self.search_with_threshold(embedding:, agent:, threshold: 0.7, limit: 10)
    results = search_similar(embedding: embedding, agent: agent, limit: limit)
    results.select { |entry| (1 - entry.neighbor_distance) >= threshold }
  end

  # Returns true if this entry has a usable embedding
  def embedded?
    embedding.present?
  end
end
