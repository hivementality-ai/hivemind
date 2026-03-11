# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamChats::Export do
  let(:user) { create(:user) }
  let(:team) { create(:team) }
  let(:agent1) { create(:agent, name: "Cody", role: "Developer", llm_model: "claude-sonnet-4-5") }
  let(:agent2) { create(:agent, name: "Scout", role: "Researcher", llm_model: "claude-haiku-4-5") }
  let(:tcs) { create(:team_chat_session, team: team, user: user) }

  before do
    team.agents << [agent1, agent2]

    create(:team_chat_message,
      team_chat_session: tcs,
      sender_type: "user",
      sender_id: user.id,
      content: "Investigate the API issue"
    )

    create(:team_chat_message,
      team_chat_session: tcs,
      sender_type: "agent",
      sender_id: agent1.id,
      content: "On it, checking logs."
    )
  end

  describe ".call" do
    subject(:result) { described_class.call(team_chat_session: tcs) }

    it "returns a team_chat export hash" do
      expect(result[:export_type]).to eq("team_chat")
      expect(result[:exported_at]).to be_present
    end

    it "includes team chat session metadata" do
      expect(result[:team_chat_session][:id]).to eq(tcs.id)
      expect(result[:team_chat_session][:session_key]).to eq(tcs.session_key)
    end

    it "includes team info" do
      expect(result[:team][:id]).to eq(team.id)
      expect(result[:team][:name]).to eq(team.name)
    end

    it "lists agents" do
      names = result[:agents].map { |a| a[:name] }
      expect(names).to include("Cody", "Scout")
    end

    it "builds a timeline from messages" do
      timeline = result[:timeline]
      expect(timeline.size).to eq(2)
      expect(timeline[0][:type]).to eq("user_message")
      expect(timeline[0][:content]).to eq("Investigate the API issue")
      expect(timeline[1][:type]).to eq("agent_message")
      expect(timeline[1][:sender_name]).to eq("Cody")
    end

    it "includes sequential indices" do
      timeline = result[:timeline]
      expect(timeline.map { |e| e[:index] }).to eq([0, 1])
    end

    it "includes tool executions summary" do
      expect(result[:tool_executions_summary][:total]).to eq(0)
    end
  end
end
