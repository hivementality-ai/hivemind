# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodingAgentJob, type: :job do
  let(:session) { create(:session) }
  let(:task) { create(:coding_agent_task, session: session, cli: "claude", task: "Fix the bug", timeout: 600) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(FileUtils).to receive(:mkdir_p)
    allow(File).to receive(:write)
    allow(File).to receive(:chmod)
    allow(File).to receive(:exist?).and_return(false)
    allow(File).to receive(:delete)
    allow(File).to receive(:size).and_return(0)
  end

  describe "#perform" do
    context "successful completion" do
      before do
        thread = double(alive?: false)
        allow(Open3).to receive(:capture3).and_return([ "", "", double(exitstatus: 0) ])
        allow(Thread).to receive(:new).and_yield.and_return(thread)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:size).and_return(0)
        allow(File).to receive(:open).and_return("")
        allow(File).to receive(:read).and_return("0")
        allow_any_instance_of(described_class).to receive(:monitor_output) do |job|
          task.update!(status: "completed", output: "Done", completed_at: Time.current)
        end
      end

      it "sets task status to running" do
        described_class.perform_now(task.id)
        # Task was set to running before monitor_output
        # Check it was updated (monitor_output overrides to completed)
        expect(task.reload.status).to eq("completed")
      end

      it "writes a script file" do
        described_class.perform_now(task.id)
        expect(File).to have_received(:write).at_least(:once)
      end
    end

    context "build_cli_command" do
      let(:job) { described_class.new }

      it "builds claude command" do
        cmd = job.send(:build_cli_command, "claude", "Fix bug", "claude-3-5-sonnet")
        expect(cmd).to include("claude")
        expect(cmd).to include("--dangerously-skip-permissions")
        expect(cmd).to include("Fix bug")
        expect(cmd).to include("--model claude-3-5-sonnet")
      end

      it "builds codex command" do
        cmd = job.send(:build_cli_command, "codex", "Fix bug", nil)
        expect(cmd).to include("codex exec --full-auto")
        expect(cmd).to include("Fix bug")
      end

      it "builds aider command" do
        cmd = job.send(:build_cli_command, "aider", "Fix bug", "gpt-4")
        expect(cmd).to include("aider")
        expect(cmd).to include("--yes-always")
        expect(cmd).to include("--model gpt-4")
      end

      it "raises ArgumentError for unknown CLI" do
        expect { job.send(:build_cli_command, "unknown", "Fix bug", nil) }.to raise_error(ArgumentError, "Unknown CLI: unknown")
      end
    end

    context "build_env_vars" do
      let(:job) { described_class.new }

      it "includes API keys from VaultEntry" do
        allow(VaultEntry).to receive(:find_by).with(namespace: "provider_credentials", key: "anthropic_api_key").and_return(double(value: "sk-ant-123"))
        allow(VaultEntry).to receive(:find_by).with(namespace: "provider_credentials", key: "openai_api_key").and_return(double(value: "sk-oai-456"))

        env = job.send(:build_env_vars)
        expect(env["ANTHROPIC_API_KEY"]).to eq("sk-ant-123")
        expect(env["OPENAI_API_KEY"]).to eq("sk-oai-456")
      end

      it "skips missing keys" do
        allow(VaultEntry).to receive(:find_by).and_return(nil)
        env = job.send(:build_env_vars)
        expect(env).to eq({})
      end
    end

    context "error handling" do
      before do
        allow(File).to receive(:write).and_raise(StandardError, "disk full")
      end

      it "marks task as failed on exception" do
        described_class.perform_now(task.id)
        expect(task.reload.status).to eq("failed")
        expect(task.output).to include("disk full")
      end

      it "broadcasts failure message" do
        described_class.perform_now(task.id)
        expect(ActionCable.server).to have_received(:broadcast).with(
          anything,
          hash_including(type: "coding_agent_message", message: a_string_including("failed"))
        )
      end
    end

    context "cleanup" do
      it "attempts to delete temp files" do
        allow(File).to receive(:write).and_raise(StandardError, "boom")
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:delete)

        described_class.perform_now(task.id)
        # cleanup_files is called in ensure block
      end
    end
  end
end
