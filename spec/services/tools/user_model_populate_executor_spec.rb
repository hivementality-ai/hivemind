# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::UserModelPopulateExecutor, type: :service do
  let(:agent)    { create(:agent) }
  let(:executor) { described_class.new(input: {}, agent: agent) }

  describe "#call" do
    context "when no scannable memories exist" do
      it "returns success with a no-candidates message" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No memories in scannable categories")
      end
    end

    context "when scannable memories exist but none match preference signals" do
      before do
        create(:memory_entry, agent: agent, category: "general", status: "active",
               content: "The project uses PostgreSQL as its main database")
        create(:memory_entry, agent: agent, category: "factual", status: "active",
               content: "Hivemind is built with Ruby on Rails")
      end

      it "returns success noting no matches" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("none matched preference signals")
      end

      it "reports how many were scanned" do
        result = executor.call
        expect(result.data[:output]).to include("Scanned 2 memories")
      end

      it "does not change any categories" do
        executor.call
        expect(MemoryEntry.where(agent: agent, category: "user_preference").count).to eq(0)
      end
    end

    context "when scannable memories match preference signals" do
      let!(:general_pref) do
        create(:memory_entry, agent: agent, category: "general", status: "active",
               content: "User prefers dark mode in all editors")
      end
      let!(:factual_rule) do
        create(:memory_entry, agent: agent, category: "factual", status: "active",
               content: "Strict rule: always use feature branches, never push to main")
      end
      let!(:irrelevant) do
        create(:memory_entry, agent: agent, category: "general", status: "active",
               content: "The codebase has 200 model files")
      end

      it "reclassifies matched memories to user_preference" do
        executor.call
        expect(general_pref.reload.category).to eq("user_preference")
        expect(factual_rule.reload.category).to eq("user_preference")
      end

      it "does not reclassify non-matching memories" do
        executor.call
        expect(irrelevant.reload.category).to eq("general")
      end

      it "reports the count of reclassified memories" do
        result = executor.call
        expect(result.data[:output]).to include("Reclassified 2 memor")
      end

      it "includes memory IDs in the output" do
        result = executor.call
        expect(result.data[:output]).to include("ID:#{general_pref.id}")
        expect(result.data[:output]).to include("ID:#{factual_rule.id}")
      end

      it "suggests running user_model after" do
        result = executor.call
        expect(result.data[:output]).to include("user_model")
      end
    end

    context "dry_run mode" do
      let!(:pref_memory) do
        create(:memory_entry, agent: agent, category: "general", status: "active",
               content: "User always wants a PR, never direct commits")
      end
      let(:executor) { described_class.new(input: { "dry_run" => true }, agent: agent) }

      it "does not update any categories" do
        executor.call
        expect(pref_memory.reload.category).to eq("general")
      end

      it "reports what would be reclassified" do
        result = executor.call
        expect(result.data[:output]).to include("Would reclassify")
        expect(result.data[:output]).to include("ID:#{pref_memory.id}")
      end

      it "notes that it is a dry run" do
        result = executor.call
        expect(result.data[:output]).to include("Dry run")
      end
    end

    context "does not scan already-categorized user_preference memories" do
      before do
        create(:memory_entry, agent: agent, category: "user_preference", status: "active",
               content: "User prefers dark mode")
      end

      it "reports no scannable candidates" do
        result = executor.call
        expect(result.data[:output]).to include("No memories in scannable categories")
      end
    end

    context "does not touch memories from other agents" do
      let(:other_agent) { create(:agent) }
      let!(:other_pref) do
        create(:memory_entry, agent: other_agent, category: "general", status: "active",
               content: "User always prefers feature branches")
      end

      it "ignores other agents' memories" do
        executor.call
        expect(other_pref.reload.category).to eq("general")
      end
    end

    context "without an agent" do
      let(:executor) { described_class.new(input: {}, agent: nil) }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Agent context required")
      end
    end
  end
end
