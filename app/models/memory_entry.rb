# frozen_string_literal: true

class MemoryEntry < ApplicationRecord
  belongs_to :agent
  belongs_to :source, polymorphic: true, optional: true

  has_neighbors :embedding

  validates :content, presence: true
  validates :memory_type, inclusion: { in: %w[episodic semantic procedural preference] }

  MEMORY_TYPES = {
    "episodic" => "What happened (conversation summaries, events)",
    "semantic" => "Facts and knowledge (names, roles, preferences)",
    "procedural" => "How to do things (commands, workflows)",
    "preference" => "User preferences (style, tools, habits)"
  }.freeze

  # --- Scopes ---
  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :by_type, ->(type) { where(memory_type: type) }
  scope :episodic, -> { by_type("episodic") }
  scope :semantic, -> { by_type("semantic") }
  scope :procedural, -> { by_type("procedural") }
  scope :preferences, -> { by_type("preference") }
  scope :not_consolidated, -> { where(consolidated: false) }
  scope :consolidated, -> { where(consolidated: true) }
  scope :by_importance, -> { order(importance: :desc) }
  scope :by_source_type, ->(type) { where(source_type: type) }

  # --- Vector Search ---

  # Search for similar memories using pgvector cosine similarity
  def self.search_similar(embedding:, agent:, limit: 10)
    where(agent: agent)
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .limit(limit)
  end

  # Search with a minimum similarity threshold
  # neighbor_distance is cosine distance (0 = identical, 2 = opposite)
  # threshold is similarity (1 = identical, 0 = unrelated)
  def self.search_with_threshold(embedding:, agent:, threshold: 0.7, limit: 10)
    results = search_similar(embedding: embedding, agent: agent, limit: limit)
    results.select { |entry| (1 - entry.neighbor_distance) >= threshold }
  end

  # Relevance-weighted search: 70% semantic similarity + 30% recency
  def self.relevance_search(embedding:, agent:, limit: 10, recency_half_life_days: 7)
    candidates = search_similar(embedding: embedding, agent: agent, limit: limit * 2)

    candidates.map do |entry|
      similarity = 1 - entry.neighbor_distance
      recency = recency_score(entry.created_at, half_life_days: recency_half_life_days)
      score = (0.7 * similarity) + (0.3 * recency)

      [ entry, score ]
    end.sort_by { |_, score| -score }.first(limit).map(&:first)
  end

  # --- Deduplication ---

  # Find near-duplicates for a given embedding
  def self.find_duplicate(embedding:, agent:, threshold: 0.92)
    candidates = search_similar(embedding: embedding, agent: agent, limit: 3)
    candidates.find { |entry| (1 - entry.neighbor_distance) >= threshold }
  end

  # --- Helpers ---

  def embedded?
    embedding.present?
  end

  def similarity_to(other_embedding)
    return nil unless embedded? && other_embedding.present?

    # Cosine similarity via dot product (assumes normalized vectors)
    embedding.zip(other_embedding).sum { |a, b| a * b }
  end

  # Touch last_accessed_at when a memory is retrieved
  def touch_accessed!
    update_column(:last_accessed_at, Time.current)
  end

  private

  # Exponential decay: score of 1.0 at t=0, 0.5 at t=half_life
  def self.recency_score(created_at, half_life_days: 7)
    age_days = (Time.current - created_at) / 1.day
    Math.exp(-Math.log(2) * age_days / half_life_days)
  end
end
