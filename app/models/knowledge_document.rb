# frozen_string_literal: true

# A source document ingested into the knowledge base. Text is extracted,
# chunked, embedded, and stored as KnowledgeChunks for RAG retrieval.
class KnowledgeDocument < ApplicationRecord
  belongs_to :agent
  has_many :chunks, class_name: "KnowledgeChunk", dependent: :destroy

  SOURCE_TYPES = %w[text pdf].freeze
  STATUSES     = %w[pending processing ready failed].freeze

  validates :title, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :ready,     -> { where(status: "ready") }
  scope :pending,   -> { where(status: "pending") }

  def ready?
    status == "ready"
  end
end
