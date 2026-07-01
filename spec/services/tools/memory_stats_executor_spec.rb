# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MemoryStatsExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:other_agent) { create(:agent) }
  let(:executor) { described_class.new(input: {}, agent: agent) }

  describe "#call" do
    context "with memories spread across categories and statuses" do
      before do
        create(:memory_entry, agent: agent, category: "user_preference", status: "active")
        create(:memory_entry, agent: agent, category: "user_preference", status: "active")
        create(:memory_entry, agent: agent, category: "decision",        status: "archived")
        create(:memory_entry, agent: agent, category: "factual",         status: "superseded")
        # Other agent — should not affect counts
        create(:memory_entry, agent: other_agent, category: "general", status: "active")
      end

      it "returns success" do
        result = executor.call
        expect(result).to be_success
      end

      it "shows correct per-category counts" do
        result = executor.call
        output = result.data[:output]
        expect(output).to include("user_preference: 2")
        expect(output).to include("decision: 1")
        expect(output).to include("factual: 1")
        expect(output).to include("general: 0")
        expect(output).to include("project_context: 0")
        expect(output).to include("learned_behavior: 0")
      end

      it "shows correct per-status counts" do
        result = executor.call
        output = result.data[:output]
        expect(output).to include("active: 2")
        expect(output).to include("archived: 1")
        expect(output).to include("superseded: 1")
      end

      it "shows correct total" do
        result = executor.call
        expect(result.data[:output]).to include("Total: 4")
      end

      it "scopes counts to the calling agent only" do
        result = executor.call
        # other_agent has 1 entry but total should be 4 (this agent's only)
        expect(result.data[:output]).to include("Total: 4")
      end
    end

    context "with no memories" do
      it "returns zero counts for all categories and statuses" do
        result = executor.call
        output = result.data[:output]
        expect(output).to include("Total: 0")
        MemoryEntry::CATEGORIES.each { |cat| expect(output).to include("#{cat}: 0") }
        MemoryEntry::STATUSES.each   { |st|  expect(output).to include("#{st}: 0") }
      end
    end

    context "without an agent" do
      let(:executor) { described_class.new(input: {}, agent: nil) }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("Agent context required")
      end
    end
  end
end
