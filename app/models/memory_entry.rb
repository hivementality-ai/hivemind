# frozen_string_literal: true

class MemoryEntry < ApplicationRecord
  belongs_to :agent
  belongs_to :source, polymorphic: true, optional: true

  # has_neighbors :embedding  # Disabled until pgvector is installed

  validates :content, presence: true
  # embedding not required until pgvector is fully wired

  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :by_source_type, ->(type) { where(source_type: type) }

  # Search for similar memories using vector similarity
  # Simplified version without pgvector - just returns recent entries for now
  def self.search_similar(embedding:, agent:, limit: 10)
    where(agent: agent)
      .order(created_at: :desc)
      .limit(limit)

    # TODO: When pgvector is installed, use:
    # where(agent: agent)
    #   .nearest_neighbors(:embedding, embedding, distance: "cosine")
    #   .limit(limit)
  end

  # Search with a minimum similarity threshold (0-1, where 1 is identical)
  def self.search_with_threshold(embedding:, agent:, threshold: 0.7, limit: 10)
    # Without pgvector, just return recent entries
    search_similar(embedding: embedding, agent: agent, limit: limit)

    # TODO: When pgvector is installed, calculate actual similarity
  end

  # Placeholder for neighbor_distance when not using pgvector
  def neighbor_distance
    0.5  # Fake distance for compatibility
  end
end
