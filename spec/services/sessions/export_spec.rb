# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::Export, type: :service do
  let(:agent) { create(:agent, name: "TestAgent", role: "Developer") }
  let(:tool) { create(:tool, name: "shell_command") }
  let(:session) do
    create(:session, :with_transcript, agent: agent, title: "Debug Session",
           conversation_summary: "A test conversation")
  end

  describe ".call" do
    subject { described_class.call(session: session) }

    context "with a basic session" do
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

      it "includes session metadata" do
        export = subject.data[:export]
        expect(export[:session][:id]).to eq(session.id)
        expect(export[:session][:title]).to eq("Debug Session")
        expect(export[:session][:session_key]).to eq(session.session_key)
        expect(export[:session][:status]).to eq("active")
      end

      it "includes agent info" do
        export = subject.data[:export]
        expect(export[:agent][:name]).to eq("TestAgent")
        expect(export[:agent][:role]).to eq("Developer")
        expect(export[:agent][:slug]).to eq(agent.slug)
      end

      it "includes usage stats" do
        export = subject.data[:export]
        expect(export[:usage][:input_tokens]).to eq(10)
        expect(export[:usage][:output_tokens]).to eq(5)
        expect(export[:usage][:total_tokens]).to eq(15)
        expect(export[:usage][:transcript_entries]).to eq(2)
      end

      it "includes conversation summary" do
        export = subject.data[:export]
        expect(export[:conversation_summary]).to eq("A test conversation")
      end
    end

    context "with transcript entries" do
      it "includes transcript entries in timeline" do
        export = subject.data[:export]
        timeline = export[:timeline]
        messages = timeline.select { |e| e[:type] == "message" }
        expect(messages.size).to eq(2)
        expect(messages.first[:role]).to eq("user")
        expect(messages.last[:role]).to eq("assistant")
      end
    end

    context "with tool executions" do
      let!(:tool_execution) do
        create(:tool_execution, :completed, tool: tool, agent: agent, session: session,
               output: "file1.txt\nfile2.txt")
      end

      it "includes tool executions in timeline" do
        export = subject.data[:export]
        timeline = export[:timeline]
        tool_entries = timeline.select { |e| e[:type] == "tool_execution" }
        expect(tool_entries.size).to eq(1)
        expect(tool_entries.first[:tool_name]).to eq("shell_command")
        expect(tool_entries.first[:status]).to eq("completed")
      end

      it "includes tool_executions_summary" do
        export = subject.data[:export]
        summary = export[:tool_executions_summary]
        expect(summary["shell_command"][:count]).to eq(1)
        expect(summary["shell_command"][:statuses]).to eq({ "completed" => 1 })
      end
    end

    context "with large tool output" do
      let!(:tool_execution) do
        create(:tool_execution, :completed, tool: tool, agent: agent, session: session,
               output: "x" * 20_000)
      end

      it "truncates tool output to 10KB" do
        export = subject.data[:export]
        tool_entry = export[:timeline].find { |e| e[:type] == "tool_execution" }
        expect(tool_entry[:output].bytesize).to be <= (10_240 + 50)
        expect(tool_entry[:output]).to include("[truncated at 10240 bytes]")
      end
    end

    context "when session has no transcript" do
      let(:session) { create(:session, agent: agent, transcript: []) }

      it "returns success with empty timeline" do
        export = subject.data[:export]
        expect(export[:timeline]).to eq([])
      end
    end

    context "when an error occurs" do
      before do
        allow(session).to receive(:agent).and_raise(StandardError, "boom")
      end

      it "returns failure" do
        result = subject
        expect(result).not_to be_success
        expect(result.error).to include("Export failed: boom")
      end
    end
  end
end
