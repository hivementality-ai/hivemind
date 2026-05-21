# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MemorySearchExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:other_agent) { create(:agent) }
  let(:embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }
  let(:executor) { described_class.new(input: input, agent: agent) }

  # Stub embedding so tests don't need a live embedding service
  before do
    allow(Memory::Embedding).to receive(:generate_query).and_return(nil)
  end

  describe "#call" do
    context "backward-compatible baseline — no filters" do
      let!(:entry1) { create(:memory_entry, agent: agent, content: "User likes dark mode", status: "active") }
      let!(:entry2) { create(:memory_entry, agent: agent, content: "User prefers concise answers", status: "active") }
      let!(:archived) { create(:memory_entry, agent: agent, content: "Old dark preference", status: "archived") }
      let(:input) { { "query" => "dark mode" } }

      it "returns success" do
        result = executor.call
        expect(result).to be_success
      end

      it "finds matching active memories" do
        result = executor.call
        expect(result.data[:output]).to include("dark mode")
      end

      it "does not return archived memories" do
        result = executor.call
        expect(result.data[:output]).not_to include("Old dark preference")
      end

      it "includes category and status metadata in each result" do
        result = executor.call
        # Format: [category/status]
        expect(result.data[:output]).to match(/\[general\/active\]/)
      end

      it "includes the memory ID in each result" do
        result = executor.call
        expect(result.data[:output]).to include("ID: #{entry1.id}")
      end
    end

    context "category filter" do
      let!(:pref_entry)    { create(:memory_entry, agent: agent, content: "dark mode pref", category: "user_preference", status: "active") }
      let!(:factual_entry) { create(:memory_entry, agent: agent, content: "dark mode fact", category: "factual",         status: "active") }
      let(:input) { { "query" => "dark mode", "category" => "user_preference" } }

      it "returns only entries with the requested category" do
        result = executor.call
        expect(result.data[:output]).to include(pref_entry.content)
        expect(result.data[:output]).not_to include(factual_entry.content)
      end
    end

    context "status filter" do
      let!(:active_entry)   { create(:memory_entry, agent: agent, content: "active dark mode setting", status: "active") }
      let!(:archived_entry) { create(:memory_entry, agent: agent, content: "archived dark mode setting", status: "archived") }
      let(:input) { { "query" => "dark mode setting", "status" => "archived" } }

      it "returns only entries with the requested status" do
        result = executor.call
        expect(result.data[:output]).to include(archived_entry.content)
        expect(result.data[:output]).not_to include(active_entry.content)
      end
    end

    context "invalid category — backward-compatible fallback" do
      let!(:entry) { create(:memory_entry, agent: agent, content: "anything here", status: "active") }
      let(:input) { { "query" => "anything", "category" => "garbage_value" } }

      it "ignores the invalid category and returns results" do
        result = executor.call
        expect(result).to be_success
      end
    end

    context "invalid status — falls back to active" do
      let!(:active_entry)   { create(:memory_entry, agent: agent, content: "active result", status: "active") }
      let!(:archived_entry) { create(:memory_entry, agent: agent, content: "archived result", status: "archived") }
      let(:input) { { "query" => "result", "status" => "totally_wrong" } }

      it "defaults to active-only results" do
        result = executor.call
        expect(result.data[:output]).to include(active_entry.content)
        expect(result.data[:output]).not_to include(archived_entry.content)
      end
    end

    context "with no matching memories" do
      let(:input) { { "query" => "xyzzy no match at all" } }

      it "returns success with a not-found message" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No memories found")
      end
    end

    context "with blank query" do
      let(:input) { { "query" => "" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No query provided")
      end
    end

    context "limit parameter" do
      let(:input) { { "query" => "important", "limit" => 2 } }

      before do
        5.times { |i| create(:memory_entry, agent: agent, content: "important memory #{i}", status: "active") }
      end

      it "respects the limit" do
        result = executor.call
        # Count "ID:" occurrences to determine how many entries are returned
        expect(result.data[:output].scan("ID:").length).to eq(2)
      end
    end

    context "semantic search path (embedding available)" do
      let!(:entry) { create(:memory_entry, agent: agent, content: "dark mode pref", status: "active", embedding: embedding) }
      let(:input)  { { "query" => "dark mode" } }

      before do
        allow(Memory::Embedding).to receive(:generate_query).and_return(embedding)
      end

      it "uses vector similarity and returns active entries" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include(entry.content)
      end

      it "excludes archived entries even in vector path" do
        archived = create(:memory_entry, agent: agent, content: "dark mode archived", status: "archived", embedding: embedding)
        result = executor.call
        expect(result.data[:output]).not_to include(archived.content)
      end
    end

    context "without an agent" do
      let(:input) { { "query" => "anything" } }
      let(:executor) { described_class.new(input: input, agent: nil) }

      it "returns no memories found (not an error)" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No memories found")
      end
    end
  end
end
