# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Tools
  class WebSearchExecutor < BaseExecutor
    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      provider = Search::Resolver.provider
      results = provider.search(
        query,
        count: (input["count"] || 5).to_i,
        country: input["country"],
        language: input["language"]
      )

      output = format_results(query, results, provider)
      ServiceResponse.success(data: { output: output, exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Search failed: #{e.message}")
    end

    private

    def format_results(query, results, provider)
      lines = []
      provider_name = provider.class.name.demodulize

      if results.empty?
        lines << "No results found for '#{query}'. Try web_fetch with a specific URL for more detailed information."
        return lines.join("\n")
      end

      results.each_with_index do |r, i|
        lines << "#{i + 1}. **#{r.title}**"
        lines << "   #{r.url}" if r.url.present?
        lines << "   #{r.snippet}" if r.snippet.present?
        lines << ""
      end

      lines << "_Search provider: #{provider_name}_"
      lines.join("\n")
    end
  end
end
