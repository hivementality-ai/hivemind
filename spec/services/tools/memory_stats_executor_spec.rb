# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MemoryStatsExecutor, type: :service do
  let(:agent)    { create(:agent) }
  let(:config)   { {} }
  let(:executor) { described_class.new(input: {}, config: config, agent: agent) }

  describe "#call" do
    context "without an agent" do
      let(:executor) { described_class.new(input: {}, config: {}, agent: nil) }

      it "returns a failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No agent context")
      end
    end

    context "with no memories" do
      it "succeeds and shows zero totals" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("0 total")
      end
    end

    context "with memories across categories and statuses" do
      before do
        create(:memory_entry, agent: agent, category: "user_preference", status: "active")
        create(:memory_entry, agent: agent, category: "user_preference", status: "active")
        create(:memory_entry, agent: agent, category: "decision",        status: "archived")
        create(:memory_entry, agent: agent, category: "general",         status: "active")
        # different agent — should not appear in counts
        other_agent = create(:agent)
        create(:memory_entry, agent: other_agent, category: "factual", status: "active")
      end

      it "returns total count scoped to this agent" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("3 total")
      end

      it "shows category breakdown" do
        result = executor.call
        expect(result.data[:output]).to include("user_preference: 2")
        expect(result.data[:output]).to include("decision: 1")
        expect(result.data[:output]).to include("general: 1")
      end

      it "shows status breakdown" do
        result = executor.call
        expect(result.data[:output]).to include("active: 2")
        expect(result.data[:output]).to include("archived: 1")
      end

      it "does not include other agents' memories" do
        result = executor.call
        # total is 3, not 4
        expect(result.data[:output]).not_to include("4 total")
      end
    end
  end
end
