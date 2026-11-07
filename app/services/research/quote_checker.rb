# frozen_string_literal: true

module Research
  # Checks every long quoted passage in a research report against the fetched text of the
  # sources. Matching is deterministic text comparison after normalization; no model is involved.
  class QuoteChecker
    MIN_WORDS = 8
    MAX_SOURCE_CHARS = 200_000
    LINK_URL = /\]\((\S+?)(?:\s+"[^"]*")?\)/
    DASHES = /[‐-―−]/
    EDGE_PUNCTUATION = /\A[\s.,;:!?-]+|[\s.,;:!?-]+\z/

    # @param report [String] the synthesized report text
    # @param sources [Array<Hash>] entries with :url and :text (the fetched source text)
    # @return [Hash] "results" (passage, source_url, status per quote; status is verified, other_source or unverified) and "summary" counts
    def self.call(report:, sources:)
      new(report: report, sources: sources).call
    end

    # Lowercases and collapses whitespace, curly quotes and unicode dashes.
    def self.normalize(text)
      text.to_s
          .tr("‘’‚‛", "'")
          .tr("“”„‟", '"')
          .gsub(DASHES, "-")
          .downcase
          .gsub(/\s+/, " ")
          .strip
    end

    def initialize(report:, sources:)
      @report = report.to_s
      @sources = Array(sources).filter_map do |source|
        text = source[:text] || source["text"]
        next if text.blank?

        { url: (source[:url] || source["url"]).to_s, text: self.class.normalize(text.first(MAX_SOURCE_CHARS)) }
      end
    end

    def call
      results = paragraphs.flat_map { |paragraph| check_paragraph(paragraph) }
      counts = results.map { |r| r["status"] }.tally
      { "results" => results,
        "summary" => { "total" => results.size, "verified" => counts.fetch("verified", 0),
                       "other_source" => counts.fetch("other_source", 0), "unverified" => counts.fetch("unverified", 0) } }
    end

    private

    def paragraphs
      @report.tr("“”„‟", '"').split(/\n{2,}/)
    end

    def check_paragraph(paragraph)
      cited = paragraph.scan(LINK_URL).flatten
      paragraph.scan(/"([^"]+)"/).flatten.filter_map do |passage|
        next if passage.split.size < MIN_WORDS

        needle = passage_key(passage)
        source = find_source(needle, cited)
        { "passage" => passage.strip, "source_url" => source&.dig(:url) || cited.first,
          "status" => status_for(source, cited) }
      end
    end

    def status_for(source, cited_urls)
      return "unverified" unless source
      return "verified" if cited_urls.empty? || cited_urls.include?(source[:url])

      "other_source"
    end

    def find_source(needle, cited_urls)
      return nil if needle.empty?

      cited = @sources.select { |s| cited_urls.include?(s[:url]) }
      (cited + @sources).find { |s| s[:text].include?(needle) }
    end

    def passage_key(passage)
      self.class.normalize(passage).gsub(EDGE_PUNCTUATION, "")
    end
  end
end
