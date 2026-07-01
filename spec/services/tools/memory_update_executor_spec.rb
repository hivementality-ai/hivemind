# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MemoryUpdateExecutor, type: :service do
  let(:agent) { create(:agent) }
  let!(:entry) { create(:memory_entry, agent: agent, content: "Original content", category: "general", status: "active") }
  let(:executor) { described_class.new(input: input, agent: agent) }

  before do
    allow(MemoryEmbeddingJob).to receive(:perform_later)
  end

  describe "#call" do
    context "updating content" do
      let(:input) { { "memory_id" => entry.id.to_s, "content" => "Updated content" } }

      it "updates the content" do
        executor.call
        expect(entry.reload.content).to eq("Updated content")
      end

      it "clears the embedding so it gets re-generated" do
        entry.update!(embedding: Array.new(768, 0.1))
        executor.call
        expect(entry.reload.embedding).to be_nil
      end

      it "queues re-embedding" do
        executor.call
        expect(MemoryEmbeddingJob).to have_received(:perform_later).with(entry.id)
      end

      it "returns success" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Memory ##{entry.id} updated")
        expect(result.data[:output]).to include("content")
      end
    end

    context "updating category" do
      let(:input) { { "memory_id" => entry.id.to_s, "category" => "decision" } }

      it "updates the category" do
        executor.call
        expect(entry.reload.category).to eq("decision")
      end

      it "does not re-queue embedding (content unchanged)" do
        executor.call
        expect(MemoryEmbeddingJob).not_to have_received(:perform_later)
      end
    end

    context "updating status" do
      let(:input) { { "memory_id" => entry.id.to_s, "status" => "archived" } }

      it "updates the status" do
        executor.call
        expect(entry.reload.status).to eq("archived")
      end
    end

    context "with invalid category" do
      let(:input) { { "memory_id" => entry.id.to_s, "category" => "made_up" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to include("Invalid category")
      end

      it "does not modify the entry" do
        executor.call
        expect(entry.reload.category).to eq("general")
      end
    end

    context "with invalid status" do
      let(:input) { { "memory_id" => entry.id.to_s, "status" => "deleted" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to include("Invalid status")
      end
    end

    context "when nothing changes (same content)" do
      let(:input) { { "memory_id" => entry.id.to_s, "content" => "Original content" } }

      it "returns success without re-queueing embedding" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No changes")
        expect(MemoryEmbeddingJob).not_to have_received(:perform_later)
      end
    end

    context "with blank content" do
      let(:input) { { "memory_id" => entry.id.to_s, "content" => "" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("content cannot be blank")
      end
    end

    context "with unknown memory_id" do
      let(:input) { { "memory_id" => "999999" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to include("not found")
      end
    end

    context "with a memory belonging to another agent" do
      let(:other_agent) { create(:agent) }
      let!(:other_entry) { create(:memory_entry, agent: other_agent, content: "Secret") }
      let(:input) { { "memory_id" => other_entry.id.to_s, "content" => "Hijacked" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to include("not found")
      end

      it "does not modify the other agent's entry" do
        executor.call
        expect(other_entry.reload.content).to eq("Secret")
      end
    end

    context "without memory_id" do
      let(:input) { { "content" => "New content" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("memory_id is required")
      end
    end

    context "without an agent" do
      let(:input) { { "memory_id" => entry.id.to_s, "content" => "x" } }
      let(:executor) { described_class.new(input: input, agent: nil) }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Agent context required")
      end
    end
  end
end
