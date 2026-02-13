# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agent, type: :model do
  describe 'associations' do
    it { should belong_to(:team).optional }
    it { should have_many(:sessions).dependent(:destroy) }
    it { should have_many(:vault_entries).dependent(:destroy) }
    it { should have_many(:usage_records).dependent(:destroy) }
    it { should have_many(:agent_budgets).dependent(:destroy) }
    it { should have_many(:scheduled_tasks).dependent(:destroy) }
    
    it { should have_many(:sent_team_messages).class_name('TeamMessage').with_foreign_key(:from_agent_id).dependent(:destroy) }
    it { should have_many(:received_team_messages).class_name('TeamMessage').with_foreign_key(:to_agent_id).dependent(:destroy) }
  end

  describe 'validations' do
    it 'validates presence of name' do
      agent = build(:agent, name: nil)
      expect(agent).not_to be_valid
      expect(agent.errors[:name]).to include("can't be blank")
    end

    it 'validates presence of role' do
      agent = build(:agent, role: nil)
      expect(agent).not_to be_valid
      expect(agent.errors[:role]).to include("can't be blank")
    end
    
    it 'validates uniqueness of name' do
      create(:agent, name: "Assistant")
      expect(build(:agent, name: "Assistant")).not_to be_valid
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(idle: 0, thinking: 1, executing: 2, waiting: 3, error: 4).with_default(:idle) }
  end

  describe 'scopes' do
    let!(:idle_agent) { create(:agent, :idle) }
    let!(:thinking_agent) { create(:agent, :thinking) }
    let!(:error_agent) { create(:agent, :error) }
    let!(:enabled_agent) { create(:agent, enabled: true) }
    let!(:disabled_agent) { create(:agent, enabled: false) }
    let(:team) { create(:team) }
    let!(:team_agent) { create(:agent, team: team) }

    describe '.active' do
      it 'returns agents not in error status' do
        expect(Agent.active).to include(idle_agent, thinking_agent)
        expect(Agent.active).not_to include(error_agent)
      end
    end

    describe '.by_team' do
      it 'returns agents for the given team' do
        expect(Agent.by_team(team)).to eq([team_agent])
      end
    end

    describe '.enabled' do
      it 'returns only enabled agents' do
        expect(Agent.enabled).to include(enabled_agent, idle_agent, thinking_agent, error_agent, team_agent)
        expect(Agent.enabled).not_to include(disabled_agent)
      end
    end
  end

  describe '#current_status' do
    it 'returns status hash with required keys' do
      agent = create(:agent, :thinking, current_task: "Processing")
      status = agent.current_status

      expect(status).to be_a(Hash)
      expect(status[:status]).to eq("thinking")
      expect(status[:current_task]).to eq("Processing")
      expect(status[:updated_at]).to be_present
    end
  end

  describe '#usage_summary' do
    let(:agent) { create(:agent) }
    
    before do
      create(:usage_record, agent: agent, cost_cents: 100, input_tokens: 50, output_tokens: 25)
      create(:usage_record, agent: agent, cost_cents: 200, input_tokens: 100, output_tokens: 50)
    end

    it 'returns usage summary with totals' do
      summary = agent.usage_summary

      expect(summary[:total_cost]).to eq(300)
      expect(summary[:total_tokens]).to eq(225)
      expect(summary[:request_count]).to eq(2)
    end
  end

  describe 'factory' do
    it 'creates a valid agent' do
      expect(build(:agent)).to be_valid
    end

    it 'creates valid agents with traits' do
      expect(build(:agent, :idle)).to be_valid
      expect(build(:agent, :thinking)).to be_valid
      expect(build(:agent, :executing)).to be_valid
      expect(build(:agent, :waiting)).to be_valid
      expect(build(:agent, :error)).to be_valid
      expect(build(:agent, :with_team)).to be_valid
      expect(build(:agent, :disabled)).to be_valid
    end
  end
end
