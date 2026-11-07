# frozen_string_literal: true

# Ingests a KnowledgeDocument: extracts text, chunks it, embeds each chunk via
# the same embedding adapter memory uses, and stores KnowledgeChunks.
class KnowledgeIngestionJob < ApplicationJob
  queue_as :low

  # ponytail: naive fixed-size word chunker with overlap. Upgrade to a
  # sentence/semantic splitter (e.g. token-aware) if retrieval quality matters.
  CHUNK_WORDS   = 800
  CHUNK_OVERLAP = 100
  PAGE_MARKER   = /\A--- Page (\d+) ---\z/

  def perform(document_id)
    document = KnowledgeDocument.find_by(id: document_id)
    return unless document

    document.update!(status: "processing", error: nil)
    document.chunks.delete_all

    text = extract_text(document)
    raise "No text extracted" if text.blank?

    chunks = document.source_type == "pdf" ? chunk_pages(text) : chunk_text(text).map { |content| { content: } }
    chunks.each_with_index do |chunk, position|
      document.chunks.create!(
        agent: document.agent,
        position: position,
        embedding: Memory::Embedding.generate(chunk[:content]),
        **chunk
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

  # Chunks PDF text carrying "--- Page N ---" markers, returning each chunk's
  # content with the first and last page its words came from.
  def chunk_pages(text)
    words = []
    pages = []
    page = 1
    text.split("\n").each do |line|
      if (marker = line.match(PAGE_MARKER))
        page = marker[1].to_i
      else
        line.split.each do |word|
          words << word
          pages << page
        end
      end
    end

    step = CHUNK_WORDS - CHUNK_OVERLAP
    (0...words.length).step(step).map do |i|
      last = [ i + CHUNK_WORDS, words.length ].min - 1
      { content: words[i..last].join(" "), page_start: pages[i], page_end: pages[last] }
    end
  end
end
