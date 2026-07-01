# frozen_string_literal: true

# Ingests a KnowledgeDocument: extracts text, chunks it, embeds each chunk via
# the same embedding adapter memory uses, and stores KnowledgeChunks.
class KnowledgeIngestionJob < ApplicationJob
  queue_as :low

  # ponytail: naive fixed-size word chunker with overlap. Upgrade to a
  # sentence/semantic splitter (e.g. token-aware) if retrieval quality matters.
  CHUNK_WORDS   = 800
  CHUNK_OVERLAP = 100

  def perform(document_id)
    document = KnowledgeDocument.find_by(id: document_id)
    return unless document

    document.update!(status: "processing", error: nil)
    document.chunks.delete_all

    text = extract_text(document)
    raise "No text extracted" if text.blank?

    chunks = chunk_text(text)
    chunks.each_with_index do |content, position|
      embedding = Memory::Embedding.generate(content)
      document.chunks.create!(
        agent: document.agent,
        content: content,
        position: position,
        embedding: embedding
      )
    end

    document.update!(status: "ready")
  rescue StandardError => e
    document&.update(status: "failed", error: e.message.truncate(500))
    Rails.logger.error("[KnowledgeIngestionJob] doc=#{document_id} failed: #{e.message}")
  end

  private

  def extract_text(document)
    case document.source_type
    when "pdf"
      result = Tools::PdfReadExecutor.new(input: { "path" => document.source_url }).call
      raise result.error unless result.success?

      result.data[:output]
    else # "text"
      raise "No source_url" if document.source_url.blank?

      File.read(document.source_url)
    end
  end

  def chunk_text(text)
    words = text.split(/\s+/)
    step  = CHUNK_WORDS - CHUNK_OVERLAP
    (0...words.length).step(step).map { |i| words[i, CHUNK_WORDS].join(" ") }
  end
end
