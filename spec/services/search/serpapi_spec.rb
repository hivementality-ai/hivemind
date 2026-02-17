# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::Serpapi do
  subject { described_class.new("test-key") }

  describe "#search" do
    it "parses SerpAPI response into results" do
      stub_request(:get, /serpapi.com/)
        .to_return(status: 200, body: {
          organic_results: [
            { title: "Result 1", link: "https://example.com/1", snippet: "First result" }
          ]
        }.to_json)

      results = subject.search("test query", count: 1)

      expect(results.size).to eq(1)
      expect(results.first.title).to eq("Result 1")
      expect(results.first.url).to eq("https://example.com/1")
    end
  end
end
