# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::TeamTokens, type: :service do
  let(:team) { create(:team, name: "Engineering") }
  let(:agent1) { create(:agent, team: team, name: "Agent1", role: "Dev") }
  let(:agent2) { create(:agent, team: team, name: "Agent2", role: "QA") }
  let(:solo_agent) { create(:agent, team: nil, name: "Solo", role: "Solo") }

  before do
    # Create usage records for team agents
    create(:usage_record, agent: agent1, input_tokens: 1000, output_tokens: 500, cost_cents: 10, provider: "anthropic")
    create(:usage_record, agent: agent1, input_tokens: 2000, output_tokens: 800, cost_cents: 15, provider: "anthropic")
    create(:usage_record, agent: agent2, input_tokens: 500, output_tokens: 200, cost_cents: 5, provider: "anthropic")

    # Create usage for unassigned agent
    create(:usage_record, agent: solo_agent, input_tokens: 300, output_tokens: 100, cost_cents: 3, provider: "openai")
  end

  describe ".call" do
    subject { described_class.call(period: "month") }

    it "returns a successful response" do
      expect(subject).to be_success
    end

    it "includes team token data" do
      data = subject.data
      expect(data[:teams]).to be_an(Array)
      expect(data[:teams].size).to eq(1)

      eng_team = data[:teams].first
      expect(eng_team[:team_name]).to eq("Engineering")
      expect(eng_team[:agent_count]).to eq(2)
      expect(eng_team[:input_tokens]).to eq(3500)
      expect(eng_team[:output_tokens]).to eq(1500)
      expect(eng_team[:total_tokens]).to eq(5000)
      expect(eng_team[:requests]).to eq(3)
    end

    it "includes unassigned agent data" do
      data = subject.data
      expect(data[:unassigned]).not_to be_nil
      expect(data[:unassigned][:team_name]).to eq("Unassigned")
      expect(data[:unassigned][:total_tokens]).to eq(400)
    end

    it "includes a summary" do
      summary = subject.data[:summary]
      expect(summary[:total_tokens]).to eq(5400)
      expect(summary[:total_requests]).to eq(4)
      expect(summary[:team_count]).to eq(1)
    end

    context "when SDK proxy is active" do
      before do
        config = create(:provider_config, adapter_type: "anthropic", enabled: true, vault_key: "provider_credentials/anthropic_api_key")
        allow(VaultEntry).to receive(:resolve).and_return(
          instance_double(VaultEntry, encrypted_value: "sk-ant-oat-test-key-12345")
        )
      end

      it "sets cost to zero for all teams" do
        data = subject.data
        expect(data[:sdk_proxy_active]).to be true

        eng_team = data[:teams].first
        expect(eng_team[:cost_cents]).to eq(0)
        expect(eng_team[:cost_dollars]).to eq(0.0)
        expect(eng_team[:sdk_proxy]).to be true

        # Tokens should still be tracked
        expect(eng_team[:total_tokens]).to eq(5000)
      end

      it "sets summary cost to zero" do
        summary = subject.data[:summary]
        expect(summary[:total_cost_cents]).to eq(0)
        expect(summary[:total_cost_dollars]).to eq(0.0)
        expect(summary[:sdk_proxy_active]).to be true
      end
    end

    context "when SDK proxy is not active" do
      before do
        config = create(:provider_config, adapter_type: "anthropic", enabled: true, vault_key: "provider_credentials/anthropic_api_key")
        allow(VaultEntry).to receive(:resolve).and_return(
          instance_double(VaultEntry, encrypted_value: "sk-ant-api03-regular-key")
        )
      end

      it "shows actual costs" do
        data = subject.data
        expect(data[:sdk_proxy_active]).to be false

        eng_team = data[:teams].first
        expect(eng_team[:cost_cents]).to eq(30)
        expect(eng_team[:sdk_proxy]).to be false
      end
    end

    context "with no teams" do
      before { Team.destroy_all }

      it "returns empty teams array" do
        result = described_class.call(period: "month")
        expect(result.data[:teams]).to eq([])
      end
    end

    context "with period filtering" do
      before do
        create(:usage_record, agent: agent1, input_tokens: 9999, output_tokens: 9999, cost_cents: 99, provider: "anthropic", created_at: 2.months.ago)
      end

      it "only includes records in the specified period" do
        result = described_class.call(period: "month")
        eng_team = result.data[:teams].first
        # Should not include the 2-month-old record
        expect(eng_team[:input_tokens]).to eq(3500)
      end
    end
  end

  describe "team_id tracking on UsageRecord" do
    it "auto-sets team_id from agent on create" do
      record = create(:usage_record, agent: agent1, provider: "anthropic")
      expect(record.team_id).to eq(team.id)
    end

    it "leaves team_id nil for unassigned agents" do
      record = create(:usage_record, agent: solo_agent, provider: "openai")
      expect(record.team_id).to be_nil
    end

    it "allows querying usage directly by team" do
      expect(team.usage_records.count).to eq(3)
      expect(team.usage_records.sum(:input_tokens)).to eq(3500)
    end
  end
end
