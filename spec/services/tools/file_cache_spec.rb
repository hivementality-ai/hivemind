# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::FileCache do
  let(:session) { double("Session", id: 42) }

  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
  end

  describe ".try_read_hit" do
    it "returns nil when nothing is cached" do
      expect(described_class.try_read_hit(session: session, path: "README.md")).to be_nil
    end

    it "returns a short cached marker after a record_read" do
      described_class.record_read(session: session, path: "README.md", content: "full text")

      hit = described_class.try_read_hit(session: session, path: "README.md")

      expect(hit).not_to be_nil
      expect(hit[:hit]).to be(true)
      expect(hit[:output]).to include("[cached]")
      expect(hit[:output]).to include("sha256:")
    end

    it "scopes entries by session" do
      described_class.record_read(session: session, path: "README.md", content: "a")

      other_session = double("Session", id: 99)
      expect(described_class.try_read_hit(session: other_session, path: "README.md")).to be_nil
    end

    it "returns nil after invalidation" do
      described_class.record_read(session: session, path: "a.rb", content: "x")
      described_class.invalidate(session: session, path: "a.rb")

      expect(described_class.try_read_hit(session: session, path: "a.rb")).to be_nil
    end

    it "returns nil when session is nil" do
      expect(described_class.try_read_hit(session: nil, path: "x")).to be_nil
    end

    it "returns nil when path is blank" do
      described_class.record_read(session: session, path: "README.md", content: "a")
      expect(described_class.try_read_hit(session: session, path: "")).to be_nil
    end
  end

  describe "#record_read" do
    it "returns the sha256 hash of content" do
      hash = described_class.record_read(session: session, path: "a.rb", content: "hello")
      expect(hash).to eq(Digest::SHA256.hexdigest("hello"))
    end
  end
end
