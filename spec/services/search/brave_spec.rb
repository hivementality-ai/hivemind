# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::Brave do
  subject { described_class.new("test-key") }

  describe "#search" do
    it "parses Brave API response into results" do
      stub_request(:get, /api.search.brave.com/)
        .to_return(status: 200, body: {
          web: {
            results: [
              { title: "Ruby Lang", url: "https://ruby-lang.org", description: "A dynamic language" },
              { title: "Rails", url: "https://rubyonrails.org", description: "Web framework" }
            ]
          }
        }.to_json)

      results = subject.search("ruby programming", count: 2)

      expect(results.size).to eq(2)
      expect(results.first).to be_a(Search::Base::Result)
      expect(results.first.title).to eq("Ruby Lang")
      expect(results.first.url).to eq("https://ruby-lang.org")
    end

    it "sends API key in header" do
      stub = stub_request(:get, /api.search.brave.com/)
        .with(headers: { "X-Subscription-Token" => "test-key" })
        .to_return(status: 200, body: { web: { results: [] } }.to_json)

      subject.search("test")
      expect(stub).to have_been_requested
    end
  end
end
