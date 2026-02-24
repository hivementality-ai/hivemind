# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CodingAgentExecutor do
  subject { described_class.new(input: input, config: config, agent: agent) }

  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:config) { { session: session } }
  let(:input) { { "task" => task } }
  let(:task) { "Add user authentication with Devise" }

  before do
    allow(SecureRandom).to receive(:hex).and_return("abc123")
    allow(CodingAgentJob).to receive(:perform_later)
  end

  describe "#call" do
    context "with valid task" do
      it "creates coding agent task with claude by default" do
        expect {
          subject.call
        }.to change { CodingAgentTask.count }.by(1)

        task = CodingAgentTask.last
        expect(task.agent).to eq(agent)
        expect(task.session).to eq(session)
        expect(task.task).to eq("Add user authentication with Devise")
        expect(task.cli).to eq("claude")
        expect(task.timeout).to eq(600)
        expect(task.task_key).to eq("abc123")
        expect(task.status).to eq("pending")
      end

      it "starts background job" do
        result = subject.call
        expect(CodingAgentJob).to have_received(:perform_later).with(CodingAgentTask.last.id)
      end

      it "returns task_key immediately" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:task_key]).to eq("abc123")
        expect(result.data[:exit_code]).to eq(0)
        expect(result.data[:output]).to include("Started claude coding agent")
        expect(result.data[:output]).to include("Task ID: abc123")
      end

      it "uses specified cli" do
        input["cli"] = "aider"

        subject.call
        task = CodingAgentTask.last
        expect(task.cli).to eq("aider")
      end

      it "stores model when provided" do
        input["model"] = "claude-sonnet"

        subject.call
        task = CodingAgentTask.last
        expect(task.model).to eq("claude-sonnet")
      end

      it "uses custom timeout when provided" do
        input["timeout"] = 300

        subject.call
        task = CodingAgentTask.last
        expect(task.timeout).to eq(300)
      end

      it "caps timeout at maximum" do
        input["timeout"] = 3600 # 1 hour, should be capped to 1800

        subject.call
        task = CodingAgentTask.last
        expect(task.timeout).to eq(1800)
      end

      it "uses codex cli" do
        input["cli"] = "codex"

        subject.call
        task = CodingAgentTask.last
        expect(task.cli).to eq("codex")
      end
    end

    context "with invalid input" do
      it "rejects empty task" do
        input["task"] = ""

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("No task provided")
        expect(CodingAgentTask.count).to eq(0)
      end

      it "rejects invalid CLI choice" do
        input["cli"] = "invalid-cli"

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Invalid CLI. Allowed: claude, codex, aider")
        expect(CodingAgentTask.count).to eq(0)
      end

      it "accepts task with backticks (escaped via Shellwords)" do
        input["task"] = "Add authentication `rm -rf /`"

        result = subject.call
        expect(result).to be_success
        expect(CodingAgentTask.count).to eq(1)
      end

      it "accepts task with single quotes (escaped via Shellwords)" do
        input["task"] = "Add authentication with 'Devise'"

        result = subject.call
        expect(result).to be_success
        expect(CodingAgentTask.count).to eq(1)
      end

      it "accepts task with dollar signs (escaped via Shellwords)" do
        input["task"] = "Add $USER authentication"

        result = subject.call
        expect(result).to be_success
        expect(CodingAgentTask.count).to eq(1)
      end
    end

    context "with no session context" do
      let(:config) { {} }

      it "finds session from agent" do
        create(:session, agent: agent, updated_at: 1.hour.ago)
        recent_session = create(:session, agent: agent, updated_at: 1.minute.ago)

        subject.call
        task = CodingAgentTask.last
        expect(task.session).to eq(recent_session)
      end

      it "works with no agent context but with session" do
        other_agent = create(:agent)
        other_session = create(:session, agent: other_agent)
        subject_no_agent = described_class.new(input: input, config: { session: other_session }, agent: nil)

        expect {
          result = subject_no_agent.call
          expect(result).to be_success
        }.to change { CodingAgentTask.count }.by(1)

        task = CodingAgentTask.last
        expect(task.agent).to eq(other_agent) # Uses session's agent
        expect(task.session).to eq(other_session)
      end
    end

    context "when task creation fails" do
      before do
        allow(CodingAgentTask).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(CodingAgentTask.new))
      end

      it "returns failure" do
        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to include("Failed to start coding agent")
      end
    end

    context "defaults to claude when cli not specified" do
      it "uses claude as default CLI" do
        subject.call
        task = CodingAgentTask.last
        expect(task.cli).to eq("claude")
      end
    end

    context "defaults timeout when not specified" do
      it "uses default timeout of 600 seconds" do
        subject.call
        task = CodingAgentTask.last
        expect(task.timeout).to eq(600)
      end
    end
  end
end
