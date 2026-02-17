# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::Duckduckgo do
  subject { described_class.new }

  describe "#search" do
    it "parses DDG instant answer response" do
      stub_request(:get, /api.duckduckgo.com/)
        .to_return(status: 200, body: {
          Heading: "Ruby (programming language)",
          Abstract: "A dynamic, open source programming language",
          AbstractURL: "https://en.wikipedia.org/wiki/Ruby_(programming_language)",
          RelatedTopics: [
            { Text: "Ruby on Rails - web framework", FirstURL: "https://duckduckgo.com/Ruby_on_Rails" }
          ]
        }.to_json)

      results = subject.search("ruby", count: 5)

      expect(results.size).to eq(2)
      expect(results.first.title).to eq("Ruby (programming language)")
      expect(results.first.snippet).to include("dynamic")
    end

    it "handles empty response" do
      stub_request(:get, /api.duckduckgo.com/)
        .to_return(status: 200, body: { Abstract: "", RelatedTopics: [] }.to_json)

      results = subject.search("asdfghjkl")
      expect(results).to be_empty
    end
  end
end
