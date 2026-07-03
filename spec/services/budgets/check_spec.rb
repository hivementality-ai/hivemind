# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::Check do
  let(:agent) { create(:agent) }

  describe ".call" do
    context "when agent has no budgets" do
      it "returns success with unlimited flag" do
        result = described_class.call(agent: agent)
        expect(result.success?).to be true
        expect(result.data[:unlimited]).to be true
      end
    end

    context "when agent has budget with remaining spend" do
      before { create(:agent_budget, agent: agent, limit_cents: 10_000, spent_cents: 5_000) }

      it "returns success" do
        result = described_class.call(agent: agent)
        expect(result.success?).to be true
      end
    end

    context "when agent has an exceeded budget" do
      before { create(:agent_budget, :exceeded, agent: agent) }

      it "returns failure" do
        result = described_class.call(agent: agent)
        expect(result.success?).to be false
      end

      it "includes an error message" do
        result = described_class.call(agent: agent)
        expect(result.error).to be_present
      end
    end

    context "when estimated cost would exceed the remaining budget" do
      before { create(:agent_budget, agent: agent, limit_cents: 10_000, spent_cents: 9_500) }

      it "returns failure when projected spend exceeds limit" do
        result = described_class.call(agent: agent, estimated_cost_cents: 600)
        expect(result.success?).to be false
      end

      it "returns success when projected spend stays within limit" do
        result = described_class.call(agent: agent, estimated_cost_cents: 400)
        expect(result.success?).to be true
      end
    end

    context "when one period is exceeded and another is not" do
      before do
        create(:agent_budget, :daily,   agent: agent, spent_cents: 0)
        create(:agent_budget, :monthly, agent: agent, spent_cents: 200_000, limit_cents: 100_000)
      end

      it "returns failure — any exceeded budget blocks the call" do
        result = described_class.call(agent: agent)
        expect(result.success?).to be false
      end
    end
  end
end
