# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::UserModelExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:executor) { described_class.new(input: {}, agent: agent) }

  describe "#call" do
    context "when no user_preference memories exist" do
      it "returns success with an empty model message" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No user preferences recorded yet")
      end

      it "hints to use memory_store or user_model_populate" do
        result = executor.call
        expect(result.data[:output]).to include("memory_store")
        expect(result.data[:output]).to include("user_model_populate")
      end
    end

    context "when user_preference memories exist" do
      before do
        create(:memory_entry, agent: agent, category: "user_preference", status: "active",
               content: "User prefers concise, direct responses without preamble")
        create(:memory_entry, agent: agent, category: "user_preference", status: "active",
               content: "Always create PRs — never push directly to main branch")
        create(:memory_entry, agent: agent, category: "user_preference", status: "active",
               content: "User works heavily with Ruby on Rails and PostgreSQL")
        create(:memory_entry, agent: agent, category: "user_preference", status: "active",
               content: "Strict rule: zero tolerance for Claude mentions in commits or PRs")
      end

      it "returns success" do
        expect(executor.call).to be_success
      end

      it "includes a User Model header with count" do
        result = executor.call
        expect(result.data[:output]).to include("## User Model (4 preferences)")
      end

      it "groups communication-style preferences under Communication Style" do
        result = executor.call
        expect(result.data[:output]).to include("### Communication Style")
        expect(result.data[:output]).to include("concise, direct responses")
      end

      it "groups workflow preferences under Workflow Preferences" do
        result = executor.call
        expect(result.data[:output]).to include("### Workflow Preferences")
        expect(result.data[:output]).to include("Always create PRs")
      end

      it "groups domain knowledge under Domain Expertise" do
        result = executor.call
        expect(result.data[:output]).to include("### Domain Expertise")
        expect(result.data[:output]).to include("Ruby on Rails")
      end

      it "groups rule-based preferences under Recurring Patterns" do
        result = executor.call
        expect(result.data[:output]).to include("### Recurring Patterns")
        expect(result.data[:output]).to include("zero tolerance")
      end

      it "includes memory IDs in the output" do
        executor.call
        entry = MemoryEntry.where(agent: agent, category: "user_preference").first
        expect(executor.call.data[:output]).to include("ID:#{entry.id}")
      end

      it "includes a footer with usage hints" do
        result = executor.call
        expect(result.data[:output]).to include("memory_search")
        expect(result.data[:output]).to include("memory_update")
      end
    end

    context "when archived user_preference memories exist" do
      before do
        create(:memory_entry, agent: agent, category: "user_preference", status: "archived",
               content: "Old preference that no longer applies")
      end

      it "excludes archived memories from the user model" do
        result = executor.call
        expect(result.data[:output]).to include("No user preferences recorded yet")
      end
    end

    context "when memories from another agent exist" do
      let(:other_agent) { create(:agent) }

      before do
        create(:memory_entry, agent: other_agent, category: "user_preference", status: "active",
               content: "Other agent's preference")
      end

      it "only returns memories for the calling agent" do
        result = executor.call
        expect(result.data[:output]).not_to include("Other agent's preference")
        expect(result.data[:output]).to include("No user preferences recorded yet")
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

    context "with preferences that don't match any keyword section" do
      before do
        create(:memory_entry, agent: agent, category: "user_preference", status: "active",
               content: "Something unusual that has no section keywords")
      end

      it "groups unmatched preferences under Other Preferences" do
        result = executor.call
        expect(result.data[:output]).to include("### Other Preferences")
        expect(result.data[:output]).to include("Something unusual")
      end
    end
  end
end
