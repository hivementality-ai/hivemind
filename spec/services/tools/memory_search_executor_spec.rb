# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MemorySearchExecutor, type: :service do
  let(:agent)    { create(:agent) }
  let(:config)   { {} }
  let(:executor) { described_class.new(input: input, config: config, agent: agent) }

  describe "#call" do
    context "without a query" do
      let(:input) { { "query" => "" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No query provided")
      end
    end

    context "with an invalid category" do
      let(:input) { { "query" => "foo", "category" => "bad_cat" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/Invalid category/)
      end
    end

    context "with an invalid status" do
      let(:input) { { "query" => "foo", "status" => "deleted" } }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to match(/Invalid status/)
      end
    end

    context "when no embedding service is available (keyword fallback)" do
      before do
        allow(Memory::Embedding).to receive(:generate_query).and_return(nil)
        create(:memory_entry, agent: agent, content: "the user prefers dark mode",
               category: "user_preference", status: "active")
        create(:memory_entry, agent: agent, content: "project uses Rails 8",
               category: "project_context", status: "active")
        create(:memory_entry, agent: agent, content: "archived old decision",
               category: "decision", status: "archived")
      end

      let(:input) { { "query" => "user prefers" } }

      it "falls back to keyword search and returns active memories" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("dark mode")
        expect(result.data[:output]).not_to include("archived old decision")
      end

      context "with category filter" do
        let(:input) { { "query" => "user", "category" => "user_preference" } }

        it "only returns memories of that category" do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("dark mode")
          expect(result.data[:output]).not_to include("Rails 8")
        end
      end

      context "with status filter" do
        let(:input) { { "query" => "old", "status" => "archived" } }

        it "returns archived memories" do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("archived old decision")
        end
      end

      context "when no memories match" do
        let(:input) { { "query" => "xyzzy_nonexistent" } }

        it "returns a no-results message" do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("No memories found")
        end
      end
    end

    context "without an agent" do
      let(:executor) { described_class.new(input: { "query" => "anything" }, config: {}, agent: nil) }

      it "returns no memories found" do
        allow(Memory::Embedding).to receive(:generate_query).and_return(nil)
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No memories found")
      end
    end
  end
end
