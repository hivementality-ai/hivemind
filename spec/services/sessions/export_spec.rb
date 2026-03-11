# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::Export do
  let(:agent) { create(:agent, name: "Cody", role: "Developer", llm_model: "claude-sonnet-4-5", model_provider: "anthropic") }
  let(:session) do
    create(:session,
      agent: agent,
      title: "Debug CSS issue",
      transcript: [
        { "role" => "user", "content" => "My CSS is broken", "timestamp" => "2026-03-09T10:00:00Z" },
        { "role" => "assistant", "content" => "Let me check the file.", "thinking" => "Need to read the CSS file", "timestamp" => "2026-03-09T10:00:05Z" }
      ],
      input_tokens: 1000,
      output_tokens: 500,
      total_tokens: 1500
    )
  end

  describe ".call" do
    subject(:result) { described_class.call(session: session) }

    it "returns a session export hash" do
      expect(result[:export_type]).to eq("session")
      expect(result[:exported_at]).to be_present
      expect(result[:hivemind_version]).to be_present
    end

    it "includes session metadata" do
      expect(result[:session][:id]).to eq(session.id)
      expect(result[:session][:title]).to eq("Debug CSS issue")
      expect(result[:session][:session_key]).to eq(session.session_key)
    end

    it "includes agent info" do
      expect(result[:agent][:name]).to eq("Cody")
      expect(result[:agent][:role]).to eq("Developer")
      expect(result[:agent][:model]).to eq("claude-sonnet-4-5")
    end

    it "includes usage with cost estimate" do
      expect(result[:usage][:input_tokens]).to eq(1000)
      expect(result[:usage][:output_tokens]).to eq(500)
      expect(result[:usage][:total_tokens]).to eq(1500)
      expect(result[:usage][:estimated_cost_cents]).to be_a(Numeric)
    end

    it "builds a timeline from transcript" do
      timeline = result[:timeline]
      expect(timeline.size).to eq(2)
      expect(timeline[0][:role]).to eq("user")
      expect(timeline[0][:content]).to eq("My CSS is broken")
      expect(timeline[1][:role]).to eq("assistant")
      expect(timeline[1][:thinking]).to eq("Need to read the CSS file")
    end

    it "includes sequential indices" do
      timeline = result[:timeline]
      expect(timeline.map { |e| e[:index] }).to eq([0, 1])
    end

    context "with tool executions" do
      let(:tool) { create(:tool, name: "file_read", enabled: true) }

      before do
        create(:tool_execution,
          tool: tool,
          agent: agent,
          session: session,
          status: "completed",
          input: { "path" => "/workspace/style.css" },
          output: ".grid { display: grid; }",
          duration_ms: 45,
          exit_code: 0
        )
      end

      it "includes tool executions in the summary" do
        summary = result[:tool_executions_summary]
        expect(summary[:total]).to eq(1)
        expect(summary[:by_tool]["file_read"][:count]).to eq(1)
        expect(summary[:by_tool]["file_read"][:success]).to eq(1)
        expect(summary[:by_tool]["file_read"][:avg_duration_ms]).to eq(45)
      end

      it "appends unmatched tool executions to timeline" do
        tool_entries = result[:timeline].select { |e| e[:role] == "tool_call" }
        expect(tool_entries.size).to eq(1)
        expect(tool_entries.first[:tool]).to eq("file_read")
        expect(tool_entries.first[:tool_status]).to eq("completed")
      end
    end
  end
end
