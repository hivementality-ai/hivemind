# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CodingAgentExecutor do
  subject { described_class.new(input: input, config: config, agent: agent) }

  let(:agent) { build(:agent) }
  let(:config) { {} }
  let(:input) { { "task" => task } }
  let(:task) { "Add user authentication with Devise" }

  # Mock VaultEntry for API keys
  let(:anthropic_entry) { build(:vault_entry, namespace: "provider_credentials", key: "anthropic_api_key", value: "test-anthropic-key") }
  let(:openai_entry) { build(:vault_entry, namespace: "provider_credentials", key: "openai_api_key", value: "test-openai-key") }

  before do
    allow(VaultEntry).to receive(:find_by).with(namespace: "provider_credentials", key: "anthropic_api_key").and_return(anthropic_entry)
    allow(VaultEntry).to receive(:find_by).with(namespace: "provider_credentials", key: "openai_api_key").and_return(openai_entry)

    # Mock file operations
    allow(FileUtils).to receive(:mkdir_p)
    allow(File).to receive(:write)
    allow(File).to receive(:chmod)
    allow(File).to receive(:delete)
    allow(File).to receive(:exist?).and_return(true)
    allow(SecureRandom).to receive(:hex).and_return("abc123")

    # Mock time for duration calculation
    allow(Process).to receive(:clock_gettime).and_return(0, 10) # 10 second duration
  end

  describe "#call" do
    context "with valid task" do
      before do
        allow(Open3).to receive(:capture3).and_return([ "Command output\n", "", double(exitstatus: 0) ])
      end

      it "builds correct claude command by default" do
        expect(Open3).to receive(:capture3).with(
          "docker", "exec", "hivemind-workspace-1",
          "bash", "-c", "timeout 600 /workspace/.hivemind/exec/abc123.sh 2>&1"
        )

        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Command output\n")
        expect(result.data[:exit_code]).to eq(0)
        expect(result.data[:duration_seconds]).to eq(10.0)
      end

      it "builds correct codex command" do
        input["cli"] = "codex"

        result = subject.call
        expect(result).to be_success
      end

      it "builds correct aider command" do
        input["cli"] = "aider"

        result = subject.call
        expect(result).to be_success
      end

      it "includes model flag when provided" do
        input["cli"] = "claude"
        input["model"] = "claude-sonnet"

        result = subject.call
        expect(result).to be_success
      end

      it "uses custom timeout when provided" do
        input["timeout"] = 300

        expect(Open3).to receive(:capture3).with(
          "docker", "exec", "hivemind-workspace-1",
          "bash", "-c", "timeout 300 /workspace/.hivemind/exec/abc123.sh 2>&1"
        )

        result = subject.call
        expect(result).to be_success
      end

      it "caps timeout at maximum" do
        input["timeout"] = 3600 # 1 hour, should be capped to 1800

        expect(Open3).to receive(:capture3).with(
          "docker", "exec", "hivemind-workspace-1",
          "bash", "-c", "timeout 1800 /workspace/.hivemind/exec/abc123.sh 2>&1"
        )

        result = subject.call
        expect(result).to be_success
      end

      it "injects API keys from vault" do
        expect(File).to receive(:write) do |_path, script_content|
          expect(script_content).to include("export ANTHROPIC_API_KEY='test-anthropic-key'")
          expect(script_content).to include("export OPENAI_API_KEY='test-openai-key'")
        end

        subject.call
      end
    end

    context "with invalid input" do
      it "rejects empty task" do
        input["task"] = ""

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("No task provided")
      end

      it "rejects invalid CLI choice" do
        input["cli"] = "invalid-cli"

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Invalid CLI. Allowed: claude, codex, aider")
      end

      it "rejects task with shell metacharacters" do
        input["task"] = "Add authentication `rm -rf /`"

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Task contains invalid characters")
      end

      it "rejects task with single quotes" do
        input["task"] = "Add authentication with 'Devise'"

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Task contains invalid characters")
      end

      it "rejects task with dollar signs" do
        input["task"] = "Add $USER authentication"

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Task contains invalid characters")
      end
    end

    context "when execution fails" do
      before do
        allow(Open3).to receive(:capture3).and_return([ "Error output\n", "stderr", double(exitstatus: 1) ])
      end

      it "returns error output with exit code" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Error output\n")
        expect(result.data[:exit_code]).to eq(1)
      end
    end

    context "when execution times out" do
      before do
        allow(Open3).to receive(:capture3).and_raise(Timeout::Error)
      end

      it "returns timeout error" do
        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Coding agent task timed out after 600s")
      end
    end

    context "when execution raises exception" do
      before do
        allow(Open3).to receive(:capture3).and_raise(StandardError, "Docker not available")
      end

      it "returns execution error" do
        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Coding agent execution failed: Docker not available")
      end
    end

    context "with missing API keys" do
      before do
        allow(VaultEntry).to receive(:find_by).and_return(nil)
        allow(Open3).to receive(:capture3).and_return([ "Output\n", "", double(exitstatus: 0) ])
      end

      it "works without API keys" do
        result = subject.call
        expect(result).to be_success
      end
    end

    context "defaults to claude when cli not specified" do
      before do
        allow(Open3).to receive(:capture3).and_return([ "Command output\n", "", double(exitstatus: 0) ])
      end

      it "uses claude as default CLI" do
        result = subject.call
        expect(result).to be_success
      end
    end

    context "defaults timeout when not specified" do
      before do
        allow(Open3).to receive(:capture3).and_return([ "Command output\n", "", double(exitstatus: 0) ])
      end

      it "uses default timeout of 600 seconds" do
        expect(Open3).to receive(:capture3).with(
          "docker", "exec", "hivemind-workspace-1",
          "bash", "-c", "timeout 600 /workspace/.hivemind/exec/abc123.sh 2>&1"
        )

        result = subject.call
        expect(result).to be_success
      end
    end
  end
end
