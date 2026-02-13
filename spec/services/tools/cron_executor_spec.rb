# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::CronExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:executor) { described_class.new(input: input, config: {}, agent: agent) }

  describe '#call' do
    context 'with list action' do
      let(:input) { { "action" => "list" } }

      context 'when tasks exist' do
        before do
          create(:scheduled_task, name: 'Daily backup', schedule: '0 2 * * *', enabled: true, agent: agent)
          create(:scheduled_task, name: 'Weekly report', schedule: 'every 1w', enabled: false, agent: agent)
        end

        it 'returns list of scheduled tasks' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("✅ [") # enabled task
          expect(result.data[:output]).to include("⏸️ [") # disabled task
          expect(result.data[:output]).to include("Daily backup — 0 2 * * *")
          expect(result.data[:output]).to include("Weekly report — every 1w")
          expect(result.data[:exit_code]).to eq(0)
        end
      end

      context 'when no tasks exist' do
        it 'returns empty message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("No scheduled tasks.")
          expect(result.data[:exit_code]).to eq(0)
        end
      end
    end

    context 'with create action' do
      let(:input) do
        {
          "action" => "create",
          "name" => "Test Task",
          "schedule" => "0 9 * * 1",
          "command" => "echo 'Monday morning'",
          "task_type" => "shell"
        }
      end

      it 'creates new scheduled task' do
        expect {
          result = executor.call
          expect(result).to be_success
        }.to change(ScheduledTask, :count).by(1)

        task = ScheduledTask.last
        expect(task.name).to eq("Test Task")
        expect(task.schedule).to eq("0 9 * * 1")
        expect(task.command).to eq("echo 'Monday morning'")
        expect(task.task_type).to eq("shell")
        expect(task.agent).to eq(agent)
        expect(task.enabled).to be true
      end

      it 'returns success with task details' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Created scheduled task: Test Task")
        expect(result.data[:output]).to include("Schedule: 0 9 * * 1")
        expect(result.data[:output]).to include("Command: echo 'Monday morning'")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'with default task_type' do
        let(:input) do
          {
            "action" => "create",
            "name" => "Simple Task",
            "schedule" => "every 5m",
            "command" => "ls -la"
          }
        end

        it 'defaults to shell task_type' do
          result = executor.call
          expect(result).to be_success
          
          task = ScheduledTask.last
          expect(task.task_type).to eq("shell")
        end
      end

      context 'without name' do
        let(:input) do
          {
            "action" => "create",
            "schedule" => "0 9 * * 1",
            "command" => "echo test"
          }
        end

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Name required")
        end
      end

      context 'without schedule' do
        let(:input) do
          {
            "action" => "create",
            "name" => "Test Task",
            "command" => "echo test"
          }
        end

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Schedule required (cron expression or 'every 5m')")
        end
      end

      context 'without command' do
        let(:input) do
          {
            "action" => "create",
            "name" => "Test Task",
            "schedule" => "0 9 * * 1"
          }
        end

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Command required")
        end
      end

      context 'with empty strings' do
        let(:input) do
          {
            "action" => "create",
            "name" => "  ",
            "schedule" => "  ",
            "command" => "  "
          }
        end

        it 'treats empty strings as missing' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Name required")
        end
      end
    end

    context 'with delete action' do
      let(:task) { create(:scheduled_task, name: 'Test Task', agent: agent) }
      let(:input) { { "action" => "delete", "task_id" => task.id.to_s } }

      it 'deletes the specified task' do
        expect {
          result = executor.call
          expect(result).to be_success
        }.to change(ScheduledTask, :count).by(-1)
        
        expect(result.data[:output]).to eq("Deleted task: Test Task")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'without task_id' do
        let(:input) { { "action" => "delete" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("task_id required")
        end
      end

      context 'with invalid task_id' do
        let(:input) { { "action" => "delete", "task_id" => "999999" } }

        it 'raises ActiveRecord::RecordNotFound' do
          expect {
            executor.call
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end

    context 'with run action' do
      let(:task) { create(:scheduled_task, name: 'Echo Task', command: 'echo "hello world"', task_type: 'shell', agent: agent) }
      let(:input) { { "action" => "run", "task_id" => task.id.to_s } }

      before do
        allow(Open3).to receive(:capture3).and_return(['hello world', '', double(exitstatus: 0)])
      end

      it 'executes the task command' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Ran task Echo Task:")
        expect(result.data[:output]).to include("hello world")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'executes command with timeout' do
        executor.call
        expect(Open3).to have_received(:capture3).with('echo "hello world"', timeout: 60)
      end

      context 'when command fails' do
        before do
          allow(Open3).to receive(:capture3).and_return(['', 'command not found', double(exitstatus: 127)])
        end

        it 'returns stderr as output with non-zero exit code' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("command not found")
          expect(result.data[:exit_code]).to eq(127)
        end
      end

      context 'with large output' do
        let(:large_output) { 'x' * 6000 }

        before do
          allow(Open3).to receive(:capture3).and_return([large_output, '', double(exitstatus: 0)])
        end

        it 'truncates output to 5000 characters' do
          result = executor.call
          expect(result).to be_success
          output_part = result.data[:output].split("\n", 2).last
          expect(output_part.length).to be <= 5000
        end
      end

      context 'with unsupported task_type' do
        let(:task) { create(:scheduled_task, name: 'Custom Task', task_type: 'custom', agent: agent) }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Unsupported task_type: custom")
        end
      end

      context 'without task_id' do
        let(:input) { { "action" => "run" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("task_id required")
        end
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown cron action: invalid")
        expect(result.error).to include("list, create, delete, run")
      end
    end

    context 'when database operation fails' do
      let(:input) { { "action" => "create", "name" => "Test", "schedule" => "invalid", "command" => "echo test" } }

      before do
        allow(ScheduledTask).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(ScheduledTask.new))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Cron error:")
      end
    end

    context 'when command execution raises exception' do
      let(:task) { create(:scheduled_task, name: 'Failing Task', command: 'echo test', agent: agent) }
      let(:input) { { "action" => "run", "task_id" => task.id.to_s } }

      before do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("Execution failed"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Cron error: Execution failed")
      end
    end
  end
end