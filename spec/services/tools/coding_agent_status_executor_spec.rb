# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CodingAgentStatusExecutor do
  subject { described_class.new(input: input, config: config, agent: agent) }

  let(:agent) { create(:agent) }
  let(:config) { {} }
  let(:input) { { "action" => action } }
  let(:action) { "status" }

  describe "#call" do
    context "status action" do
      let(:input) { { "action" => "status", "task_key" => task_key } }
      let(:task_key) { "abc123" }

      context "with valid task_key" do
        let!(:task) { create(:coding_agent_task, :running, task_key: task_key, agent: agent) }

        it "returns task status" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Coding Agent Task: #{task_key}")
          expect(result.data[:output]).to include("Status: 🔄 Running")
          expect(result.data[:output]).to include("CLI: claude")
        end

        it "shows process info for running task" do
          task.update!(process_info: { pid: 12345 })

          result = subject.call
          expect(result.data[:output]).to include("Process ID: 12345")
        end

        it "shows recent output for running task" do
          task.update!(output: "Working on authentication system...")

          result = subject.call
          expect(result.data[:output]).to include("Recent Output")
          expect(result.data[:output]).to include("Working on authentication")
        end
      end

      context "with completed task" do
        let!(:task) { create(:coding_agent_task, :completed, task_key: task_key, agent: agent) }

        it "shows full output for completed task" do
          result = subject.call
          expect(result.data[:output]).to include("Status: ✅ Completed")
          expect(result.data[:output]).to include("=== Output ===")
          expect(result.data[:output]).to include("Task completed successfully")
        end
      end

      context "with failed task" do
        let!(:task) { create(:coding_agent_task, :failed, task_key: task_key, agent: agent) }

        it "shows output for failed task" do
          result = subject.call
          expect(result.data[:output]).to include("Status: ❌ Failed")
          expect(result.data[:output]).to include("Task failed with error")
        end
      end

      context "with nonexistent task_key" do
        let(:task_key) { "nonexistent" }

        it "returns error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("Task not found: nonexistent")
        end
      end

      context "without task_key" do
        let(:input) { { "action" => "status" } }

        it "returns error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("No task_key provided")
        end
      end

      context "with task belonging to different agent" do
        let!(:task) { create(:coding_agent_task, task_key: task_key, agent: create(:agent)) }

        it "returns not found error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("Task abc123 not found or not accessible")
        end
      end
    end

    context "list action" do
      let(:action) { "list" }

      context "with tasks for current agent" do
        let!(:task1) { create(:coding_agent_task, :completed, agent: agent) }
        let!(:task2) { create(:coding_agent_task, :running, agent: agent) }
        let!(:task3) { create(:coding_agent_task, agent: create(:agent)) } # Different agent

        it "lists tasks for current agent only" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to include(task1.task_key)
          expect(result.data[:output]).to include(task2.task_key)
          expect(result.data[:output]).not_to include(task3.task_key)
        end

        it "shows status icons" do
          result = subject.call
          expect(result.data[:output]).to include("✅") # Completed task
          expect(result.data[:output]).to include("🔄") # Running task
        end

        it "shows duration for tasks" do
          result = subject.call
          expect(result.data[:output]).to include("(480.0s)") # Duration for completed task
        end
      end

      context "with no tasks" do
        it "shows no tasks message" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("No coding agent tasks found.")
        end
      end

      context "with no agent context" do
        let(:agent) { nil }
        let!(:task1) { create(:coding_agent_task, :completed) }
        let!(:task2) { create(:coding_agent_task, :running) }

        it "shows all recent tasks" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to include(task1.task_key)
          expect(result.data[:output]).to include(task2.task_key)
        end
      end
    end

    context "kill action" do
      let(:input) { { "action" => "kill", "task_key" => task_key } }
      let(:task_key) { "abc123" }

      context "with active task" do
        let!(:task) { create(:coding_agent_task, :running, task_key: task_key, agent: agent) }

        before do
          allow(Process).to receive(:kill)
        end

        it "kills the task" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to include("💀 Killed coding agent task abc123")

          task.reload
          expect(task.status).to eq("failed")
          expect(task.output).to include("Task manually killed")
          expect(task.completed_at).to be_present
        end

        it "attempts to kill process if PID exists" do
          task.update!(process_info: { pid: 12345 })

          subject.call
          expect(Process).to have_received(:kill).with("TERM", -12345)
        end

        it "handles process kill errors gracefully" do
          task.update!(process_info: { pid: 12345 })
          allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

          result = subject.call
          expect(result).to be_success
        end
      end

      context "with inactive task" do
        let!(:task) { create(:coding_agent_task, :completed, task_key: task_key, agent: agent) }

        it "returns error for inactive task" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not active")
        end
      end

      context "with nonexistent task_key" do
        let(:task_key) { "nonexistent" }

        it "returns error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("Task not found: nonexistent")
        end
      end

      context "without task_key" do
        let(:input) { { "action" => "kill" } }

        it "returns error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("No task_key provided")
        end
      end
    end

    context "invalid action" do
      let(:action) { "invalid" }

      it "returns error for unknown action" do
        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Unknown action: invalid. Supported: status, list, kill")
      end
    end

    context "when action is not specified" do
      let(:input) { { "task_key" => "abc123" } }
      let!(:task) { create(:coding_agent_task, task_key: "abc123", agent: agent) }

      it "defaults to status action" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Coding Agent Task: abc123")
      end
    end
  end
end
