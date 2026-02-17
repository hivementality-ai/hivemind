# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::Searchapi do
  subject { described_class.new("test-key") }

  describe "#search" do
    it "parses SearchAPI response into results" do
      stub_request(:get, /www.searchapi.io/)
        .to_return(status: 200, body: {
          organic_results: [
            { title: "Result 1", link: "https://example.com/1", snippet: "First result" },
            { title: "Result 2", link: "https://example.com/2", snippet: "Second result" }
          ]
        }.to_json)

      results = subject.search("test query", count: 2)

      expect(results.size).to eq(2)
      expect(results.first.title).to eq("Result 1")
      expect(results.first.url).to eq("https://example.com/1")
    end

    it "includes api_key in query params" do
      stub = stub_request(:get, /www.searchapi.io.*api_key=test-key/)
        .to_return(status: 200, body: { organic_results: [] }.to_json)

      subject.search("test")
      expect(stub).to have_been_requested
    end
  end
end
