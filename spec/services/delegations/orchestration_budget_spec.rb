# frozen_string_literal: true

require "rails_helper"

RSpec.describe Delegations::OrchestrationBudget do
  let(:orchestration_id) { SecureRandom.uuid }
  let(:agent) { create(:agent) }

  def tree_session(depth: 0)
    create(:session, agent: agent, metadata: { "orchestration_id" => orchestration_id, "delegation_depth" => depth })
  end

  describe ".spent_cents" do
    it "sums usage across all sessions in the tree" do
      create(:usage_record, session: tree_session, cost_cents: 100)
      create(:usage_record, session: tree_session(depth: 1), cost_cents: 150)
      create(:usage_record, session: create(:session, agent: agent), cost_cents: 999) # unrelated

      expect(described_class.spent_cents(orchestration_id)).to eq(250)
    end
  end

  describe ".exceeded?" do
    it "is false with no orchestration_id" do
      expect(described_class.exceeded?(nil)).to be(false)
      expect(described_class.exceeded?("")).to be(false)
    end

    it "is false under the ceiling and true at it" do
      session = tree_session
      create(:usage_record, session: session, cost_cents: Delegations::Config.orchestration_budget_cents - 1)
      expect(described_class.exceeded?(orchestration_id)).to be(false)

      create(:usage_record, session: session, cost_cents: 1)
      expect(described_class.exceeded?(orchestration_id)).to be(true)
    end

    it "honors a raised ceiling from the delegation setting" do
      Setting.set("delegation", { "orchestration_budget_cents" => 1000 }.to_json)
      create(:usage_record, session: tree_session, cost_cents: 600)

      expect(described_class.exceeded?(orchestration_id)).to be(false)
    end
  end
end
