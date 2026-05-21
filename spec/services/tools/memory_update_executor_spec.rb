# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MemoryUpdateExecutor, type: :service do
  let(:agent)    { create(:agent) }
  let(:config)   { {} }
  let(:executor) { described_class.new(input: input, config: config, agent: agent) }

  before do
    allow(Memory::Embedding).to receive(:generate).and_return(nil)
  end

  describe "#call" do
    context "without an agent" do
      let(:executor) { described_class.new(input: { "memory_id" => 1 }, config: {}, agent: nil) }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No agent context")
      end
    end

    context "without memory_id" do
      let(:input) { { "content" => "new content" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("memory_id is required")
      end
    end

    context "when memory does not exist" do
      let(:input) { { "memory_id" => 999_999, "content" => "new" } }

      it "returns not found" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/not found/)
      end
    end

    context "when memory belongs to another agent" do
      let(:other_agent) { create(:agent) }
      let!(:entry)      { create(:memory_entry, agent: other_agent) }
      let(:input)       { { "memory_id" => entry.id, "content" => "new" } }

      it "returns not found" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/not found/)
      end
    end

    context "with no fields to update" do
      let!(:entry) { create(:memory_entry, agent: agent) }
      let(:input)  { { "memory_id" => entry.id } }

      it "returns a validation error" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/Provide at least one/)
      end
    end

    context "with invalid category" do
      let!(:entry) { create(:memory_entry, agent: agent) }
      let(:input)  { { "memory_id" => entry.id, "category" => "bad" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/Invalid category/)
      end
    end

    context "with invalid status" do
      let!(:entry) { create(:memory_entry, agent: agent) }
      let(:input)  { { "memory_id" => entry.id, "status" => "deleted" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/Invalid status/)
      end
    end

    context "updating category" do
      let!(:entry) { create(:memory_entry, agent: agent, category: "general") }
      let(:input)  { { "memory_id" => entry.id, "category" => "user_preference" } }

      it "recategorizes the memory" do
        result = executor.call
        expect(result).to be_success
        expect(entry.reload.category).to eq("user_preference")
      end
    end

    context "archiving a memory" do
      let!(:entry) { create(:memory_entry, agent: agent, status: "active") }
      let(:input)  { { "memory_id" => entry.id, "status" => "archived" } }

      it "archives it" do
        result = executor.call
        expect(result).to be_success
        expect(entry.reload.status).to eq("archived")
      end
    end

    context "updating content" do
      let!(:entry) { create(:memory_entry, agent: agent, content: "old content") }
      let(:input)  { { "memory_id" => entry.id, "content" => "new content" } }

      it "updates the content" do
        result = executor.call
        expect(result).to be_success
        expect(entry.reload.content).to eq("new content")
      end

      it "reports re-vectorization in the output" do
        result = executor.call
        expect(result.data[:output]).to include("Content updated")
      end
    end

    context "updating content and category together" do
      let!(:entry) { create(:memory_entry, agent: agent, content: "old", category: "general") }
      let(:input)  { { "memory_id" => entry.id, "content" => "updated", "category" => "decision" } }

      it "applies both changes" do
        executor.call
        entry.reload
        expect(entry.content).to eq("updated")
        expect(entry.category).to eq("decision")
      end
    end
  end
end
