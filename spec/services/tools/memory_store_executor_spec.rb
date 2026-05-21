# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MemoryStoreExecutor, type: :service do
  let(:agent)    { create(:agent) }
  let(:config)   { {} }
  let(:executor) { described_class.new(input: input, config: config, agent: agent) }

  before do
    # Avoid real embedding calls in unit tests
    allow(Memory::Embedding).to receive(:generate).and_return(nil)
    allow(Memory::Embedding).to receive(:generate_query).and_return(nil)
  end

  describe "#call" do
    context "without an agent" do
      let(:executor) { described_class.new(input: { "content" => "x" }, config: {}, agent: nil) }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No agent context")
      end
    end

    context "with blank content" do
      let(:input) { { "content" => "" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("content is required")
      end
    end

    context "with an invalid category" do
      let(:input) { { "content" => "something", "category" => "invalid" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/Invalid category/)
      end
    end

    context "with valid content and default category" do
      let(:input) { { "content" => "The user likes concise replies" } }

      it "creates a memory with general category" do
        expect { executor.call }.to change { MemoryEntry.count }.by(1)
        result = executor.call
        expect(result).to be_success
        entry = MemoryEntry.where(agent: agent).last
        expect(entry.category).to eq("general")
        expect(entry.status).to eq("active")
      end

      it "returns the new memory ID in the output" do
        result = executor.call
        expect(result.data[:output]).to match(/Memory stored \(ID: \d+/)
      end
    end

    context "with explicit category" do
      let(:input) { { "content" => "User prefers dark mode", "category" => "user_preference" } }

      it "stores the memory with the given category" do
        executor.call
        entry = MemoryEntry.where(agent: agent).last
        expect(entry.category).to eq("user_preference")
      end
    end

    context "with related_memory_id" do
      let!(:old_entry) do
        create(:memory_entry, agent: agent, content: "old pref", category: "user_preference", status: "active")
      end
      let(:input) do
        { "content" => "new pref", "category" => "user_preference", "related_memory_id" => old_entry.id }
      end

      it "archives the old memory" do
        executor.call
        expect(old_entry.reload.status).to eq("archived")
      end

      it "sets superseded_by_id on the old memory" do
        executor.call
        new_entry = MemoryEntry.where(agent: agent).last
        expect(old_entry.reload.superseded_by_id).to eq(new_entry.id)
      end

      it "reports the supersede in the output" do
        result = executor.call
        expect(result.data[:output]).to include("Archived memory ##{old_entry.id}")
      end
    end

    context "with related_memory_id from a different agent" do
      let(:other_agent) { create(:agent) }
      let!(:other_entry) { create(:memory_entry, agent: other_agent, content: "other agent mem") }
      let(:input) { { "content" => "new", "related_memory_id" => other_entry.id } }

      it "returns not found" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/not found/)
      end
    end
  end
end
