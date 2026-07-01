# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MemoryStoreExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:input) { { "content" => "User prefers dark mode" } }
  let(:executor) { described_class.new(input: input, agent: agent) }

  before do
    allow(MemoryEmbeddingJob).to receive(:perform_later)
  end

  describe "#call" do
    context "happy path — content only" do
      it "creates a memory with default general category" do
        expect { executor.call }.to change(MemoryEntry, :count).by(1)
        entry = MemoryEntry.last
        expect(entry.content).to eq("User prefers dark mode")
        expect(entry.category).to eq("general")
        expect(entry.status).to eq("active")
        expect(entry.agent).to eq(agent)
      end

      it "queues embedding generation" do
        executor.call
        expect(MemoryEmbeddingJob).to have_received(:perform_later).with(MemoryEntry.last.id)
      end

      it "returns success with the new memory ID" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Memory stored")
        expect(result.data[:output]).to include("ID: #{MemoryEntry.last.id}")
      end
    end

    context "with explicit category" do
      let(:input) { { "content" => "User prefers dark mode", "category" => "user_preference" } }

      it "stores the memory with the given category" do
        executor.call
        expect(MemoryEntry.last.category).to eq("user_preference")
      end

      it "includes category in the response" do
        result = executor.call
        expect(result.data[:output]).to include("user_preference")
      end
    end

    context "with invalid category" do
      let(:input) { { "content" => "Some content", "category" => "nonsense" } }

      it "falls back to general" do
        executor.call
        expect(MemoryEntry.last.category).to eq("general")
      end
    end

    context "with related_memory_id (supersede)" do
      let!(:old_entry) { create(:memory_entry, agent: agent, status: "active") }
      let(:input) do
        { "content" => "Updated preference", "related_memory_id" => old_entry.id.to_s }
      end

      it "creates the new memory" do
        expect { executor.call }.to change(MemoryEntry, :count).by(1)
      end

      it "marks the old memory as superseded" do
        executor.call
        expect(old_entry.reload.status).to eq("superseded")
        expect(old_entry.reload.superseded_by).to eq(MemoryEntry.last)
      end

      it "mentions the superseded ID in the response" do
        result = executor.call
        expect(result.data[:output]).to include("Superseded memory ##{old_entry.id}")
      end
    end

    context "with a related_memory_id belonging to another agent" do
      let(:other_agent) { create(:agent) }
      let!(:other_entry) { create(:memory_entry, agent: other_agent, status: "active") }
      let(:input) do
        { "content" => "New content", "related_memory_id" => other_entry.id.to_s }
      end

      it "creates the memory but does not touch the other agent's entry" do
        executor.call
        expect(other_entry.reload.status).to eq("active")
      end
    end

    context "with blank content" do
      let(:input) { { "content" => "   " } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No content provided")
      end

      it "does not create a memory" do
        expect { executor.call }.not_to change(MemoryEntry, :count)
      end
    end

    context "without an agent" do
      let(:executor) { described_class.new(input: input, agent: nil) }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Agent context required")
      end
    end
  end
end
