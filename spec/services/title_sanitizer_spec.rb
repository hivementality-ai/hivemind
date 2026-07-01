# frozen_string_literal: true

require "rails_helper"

RSpec.describe TitleSanitizer do
  describe ".refusal?" do
    it "rejects identity/refusal leaks that must never become titles" do
      [
        "I appreciate the reference, but I should clarify—I'm Claude, an AI assistant made by Anthropic.",
        "I'm Claude, an AI assistant.",
        "As an AI, I cannot title this.",
        "I can't help with that"
      ].each do |leak|
        expect(described_class.refusal?(leak)).to be(true), "expected to reject: #{leak.inspect}"
      end
    end

    it "keeps real titles" do
      [ "Deploying the staging cluster", "Budget review for Q3", "Cant Stop the Music" ].each do |title|
        expect(described_class.refusal?(title)).to be(false), "expected to keep: #{title.inspect}"
      end
    end
  end

  describe ".request" do
    it "wraps the transcript as data with the instruction first" do
      out = described_class.request("User: hi\nAssistant: hello")
      expect(out).to include("<transcript>").and include("User: hi")
      expect(out).to start_with("Write a title")
    end
  end
end
