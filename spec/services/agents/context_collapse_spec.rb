# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ContextCollapse do
  describe ".call" do
    it "returns nil when there aren't enough messages to collapse" do
      msgs = Array.new(5) { |i| { "role" => "user", "content" => "m#{i}" } }
      expect(described_class.call(msgs, threshold: 1000, keep_recent: 6)).to be_nil
    end

    it "snips the middle while keeping system + first user + recent tail" do
      msgs = [
        { "role" => "system", "content" => "sys" },
        { "role" => "user",   "content" => "original request" },
        *Array.new(20) { |i| { "role" => "user", "content" => "middle #{i}" } },
        *Array.new(6)  { |i| { "role" => "user", "content" => "recent #{i}" } }
      ]

      result = described_class.call(msgs, threshold: 10_000, keep_recent: 6)

      expect(result).not_to be_nil
      expect(result.first["content"]).to eq("sys")
      expect(result[1]["content"]).to eq("original request")
      expect(result[2]["content"]).to include("earlier messages snipped")
      expect(result.last["content"]).to eq("recent 5")
    end

    it "returns nil when collapse alone would still exceed threshold" do
      huge = "x" * 50_000
      msgs = Array.new(20) { |i| { "role" => "user", "content" => "#{huge} #{i}" } }

      expect(described_class.call(msgs, threshold: 100, keep_recent: 6)).to be_nil
    end
  end
end
