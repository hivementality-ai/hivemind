# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamChats::Export, type: :service do
  let(:team) { create(:team, name: "Alpha Team") }
  let(:user) { create(:user) }
  let(:agent1) { create(:agent, name: "Agent One", team: team) }
  let(:agent2) { create(:agent, name: "Agent Two", team: team) }
  let(:tool) { create(:tool, name: "web_search") }
  let(:chat_session) { create(:team_chat_session, team: team, user: user, title: "Team Debug") }

  describe ".call" do
    subject { described_class.call(session: chat_session) }

    context "with a basic team chat" do
      it "returns success with export data" do
        result = subject
        expect(result).to be_success
        expect(result.data[:export]).to be_a(Hash)
      end

      it "includes version and exported_at" do
        export = subject.data[:export]
        expect(export[:version]).to eq("1.0")
        expect(export[:exported_at]).to be_present
      end

      it "includes team chat metadata" do
        export = subject.data[:export]
        expect(export[:team_chat][:id]).to eq(chat_session.id)
        expect(export[:team_chat][:title]).to eq("Team Debug")
      end

      it "includes team info" do
        export = subject.data[:export]
        expect(export[:team][:name]).to eq("Alpha Team")
      end
    end

    context "with team chat messages" do
      let!(:msg1) do
        create(:team_chat_message, team_chat_session: chat_session,
               sender_type: "user", sender_id: user.id, content: "Hello team!")
      end
      let!(:msg2) do
        create(:team_chat_message, team_chat_session: chat_session,
               sender_type: "agent", sender_id: agent1.id, content: "Hi there!",
               target_agent: agent1)
      end

      it "includes messages in timeline" do
        export = subject.data[:export]
        team_messages = export[:timeline].select { |e| e[:type] == "team_message" }
        expect(team_messages.size).to eq(2)
        expect(team_messages.first[:content]).to eq("Hello team!")
        expect(team_messages.first[:sender_type]).to eq("user")
      end
    end

    context "with agent sub-sessions" do
      let!(:agent_session) do
        chat_session.session_for(agent1).tap do |s|
          s.update!(
            transcript: [
              { "role" => "user", "content" => "Help me", "timestamp" => Time.current.iso8601 },
              { "role" => "assistant", "content" => "Sure!", "timestamp" => Time.current.iso8601 }
            ],
            input_tokens: 50,
            output_tokens: 25,
            total_tokens: 75
          )
        end
      end

      it "includes agent session info" do
        export = subject.data[:export]
        expect(export[:agents].size).to eq(1)
        expect(export[:agents].first[:name]).to eq("Agent One")
        expect(export[:agents].first[:tokens][:total]).to eq(75)
      end

      it "includes agent transcript entries in timeline" do
        export = subject.data[:export]
        agent_messages = export[:timeline].select { |e| e[:type] == "agent_message" }
        expect(agent_messages.size).to eq(2)
        expect(agent_messages.first[:agent]).to eq("Agent One")
      end

      it "includes usage stats" do
        export = subject.data[:export]
        expect(export[:usage][:total_tokens]).to eq(75)
        expect(export[:usage][:total_agent_sessions]).to eq(1)
      end
    end

    context "with tool executions in agent sub-sessions" do
      let!(:agent_session) { chat_session.session_for(agent1) }
      let!(:tool_execution) do
        create(:tool_execution, :completed, tool: tool, agent: agent1,
               session: agent_session, output: "search results")
      end

      it "includes tool executions in timeline" do
        export = subject.data[:export]
        tool_entries = export[:timeline].select { |e| e[:type] == "tool_execution" }
        expect(tool_entries.size).to eq(1)
        expect(tool_entries.first[:tool_name]).to eq("web_search")
        expect(tool_entries.first[:agent]).to eq("Agent One")
      end

      it "includes tool_executions_summary" do
        export = subject.data[:export]
        summary = export[:tool_executions_summary]
        expect(summary["web_search"][:count]).to eq(1)
        expect(summary["web_search"][:agents]).to include("Agent One")
      end
    end

    context "when an error occurs" do
      before do
        allow(chat_session).to receive(:team).and_raise(StandardError, "db error")
      end

      it "returns failure" do
        result = subject
        expect(result).not_to be_success
        expect(result.error).to include("Export failed: db error")
      end
    end
  end
end
