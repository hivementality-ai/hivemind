# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::HeartbeatWriteExecutor, type: :service do
  let(:agent) { create(:agent, name: 'Test Agent') }
  let(:executor) { described_class.new(input: input, config: {}, agent: agent) }

  before do
    # Clear any existing heartbeat tasks
    Setting.set("heartbeat_tasks", "[]")
  end

  describe '#call' do
    context 'with add action' do
      let(:input) { { "action" => "add", "task" => "Check email inbox" } }

      it 'adds task to heartbeat checklist' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Added to heartbeat checklist: Check email inbox")
        expect(result.data[:output]).to include("1 total tasks")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'stores task with metadata' do
        freeze_time do
          executor.call
          
          tasks = JSON.parse(Setting.get("heartbeat_tasks"))
          expect(tasks.size).to eq(1)
          expect(tasks.first["task"]).to eq("Check email inbox")
          expect(tasks.first["added_by"]).to eq("Test Agent")
          expect(tasks.first["added_at"]).to eq(Time.current.iso8601)
        end
      end

      context 'without task' do
        let(:input) { { "action" => "add" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No task provided")
        end
      end

      context 'with empty task' do
        let(:input) { { "action" => "add", "task" => "  " } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No task provided")
        end
      end

      context 'when adding multiple tasks' do
        it 'increments total count' do
          executor.call
          
          executor2 = described_class.new(input: { "action" => "add", "task" => "Review calendar" }, config: {}, agent: agent)
          result = executor2.call
          
          expect(result.data[:output]).to include("2 total tasks")
        end
      end

      context 'without agent' do
        let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

        it 'stores task without added_by' do
          executor.call
          
          tasks = JSON.parse(Setting.get("heartbeat_tasks"))
          expect(tasks.first["added_by"]).to be_nil
        end
      end
    end

    context 'with default action (add)' do
      let(:input) { { "task" => "Default action task" } }

      it 'defaults to add when no action specified' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Added to heartbeat checklist: Default action task")
      end
    end

    context 'with remove action' do
      before do
        # Add some tasks first
        Setting.set("heartbeat_tasks", [
          { "task" => "Check email inbox", "added_by" => "Agent1", "added_at" => "2023-01-01" },
          { "task" => "Review calendar events", "added_by" => "Agent2", "added_at" => "2023-01-02" },
          { "task" => "Check system status", "added_by" => "Agent1", "added_at" => "2023-01-03" }
        ].to_json)
      end

      context 'with exact match' do
        let(:input) { { "action" => "remove", "task" => "Check email inbox" } }

        it 'removes matching tasks' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("Removed 1 task(s) matching 'Check email inbox'.")
          expect(result.data[:exit_code]).to eq(0)
        end

        it 'updates stored tasks' do
          executor.call
          
          tasks = JSON.parse(Setting.get("heartbeat_tasks"))
          expect(tasks.size).to eq(2)
          expect(tasks.none? { |t| t["task"].include?("email") }).to be true
        end
      end

      context 'with partial match' do
        let(:input) { { "action" => "remove", "task" => "check" } }

        it 'removes all matching tasks (case insensitive)' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("Removed 2 task(s) matching 'check'.")
        end
      end

      context 'with no matches' do
        let(:input) { { "action" => "remove", "task" => "nonexistent task" } }

        it 'reports no matches' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("No matching tasks found.")
          expect(result.data[:exit_code]).to eq(0)
        end
      end

      context 'without task' do
        let(:input) { { "action" => "remove" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No task provided")
        end
      end
    end

    context 'with list action' do
      let(:input) { { "action" => "list" } }

      context 'with tasks present' do
        before do
          Setting.set("heartbeat_tasks", [
            { "task" => "Check email inbox", "added_by" => "Agent1", "added_at" => "2023-01-01" },
            { "task" => "Review calendar events", "added_by" => "Agent2", "added_at" => "2023-01-02" }
          ].to_json)
        end

        it 'lists all tasks with metadata' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Heartbeat checklist:")
          expect(result.data[:output]).to include("1. Check email inbox (added by Agent1)")
          expect(result.data[:output]).to include("2. Review calendar events (added by Agent2)")
          expect(result.data[:exit_code]).to eq(0)
        end
      end

      context 'with tasks missing added_by' do
        before do
          Setting.set("heartbeat_tasks", [
            { "task" => "Legacy task", "added_at" => "2023-01-01" }
          ].to_json)
        end

        it 'shows unknown for missing added_by' do
          result = executor.call
          expect(result.data[:output]).to include("1. Legacy task (added by unknown)")
        end
      end

      context 'with no tasks' do
        it 'shows empty message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("Heartbeat checklist is empty.")
          expect(result.data[:exit_code]).to eq(0)
        end
      end
    end

    context 'with clear action' do
      let(:input) { { "action" => "clear" } }

      context 'with existing tasks' do
        before do
          Setting.set("heartbeat_tasks", [
            { "task" => "Task 1", "added_by" => "Agent1" },
            { "task" => "Task 2", "added_by" => "Agent2" }
          ].to_json)
        end

        it 'clears all tasks' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("Heartbeat checklist cleared.")
          expect(result.data[:exit_code]).to eq(0)
        end

        it 'updates stored tasks to empty array' do
          executor.call
          
          tasks = JSON.parse(Setting.get("heartbeat_tasks"))
          expect(tasks).to eq([])
        end
      end

      context 'with no existing tasks' do
        it 'still shows cleared message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("Heartbeat checklist cleared.")
        end
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid", "task" => "Some task" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("add, remove, list, clear")
      end
    end

    context 'when settings operations fail' do
      let(:input) { { "action" => "add", "task" => "Test task" } }

      before do
        allow(Setting).to receive(:set).and_raise(StandardError.new("Database error"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Heartbeat write failed: Database error")
      end
    end

    context 'with corrupt heartbeat_tasks JSON' do
      before do
        # Set invalid JSON
        allow(Setting).to receive(:get).with("heartbeat_tasks").and_return("invalid json")
      end

      context 'when adding task' do
        let(:input) { { "action" => "add", "task" => "New task" } }

        it 'handles corrupt JSON gracefully' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("1 total tasks")
        end
      end

      context 'when listing tasks' do
        let(:input) { { "action" => "list" } }

        it 'shows empty list for corrupt JSON' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("Heartbeat checklist is empty.")
        end
      end
    end

    context 'when heartbeat_tasks setting is nil' do
      before do
        allow(Setting).to receive(:get).with("heartbeat_tasks").and_return(nil)
      end

      context 'when listing' do
        let(:input) { { "action" => "list" } }

        it 'shows empty list' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("Heartbeat checklist is empty.")
        end
      end

      context 'when adding' do
        let(:input) { { "action" => "add", "task" => "First task" } }

        it 'creates new task list' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("1 total tasks")
        end
      end
    end

    context 'with case sensitivity in remove' do
      before do
        Setting.set("heartbeat_tasks", [
          { "task" => "Check Email Inbox", "added_by" => "Agent1" },
          { "task" => "review calendar events", "added_by" => "Agent2" }
        ].to_json)
      end

      let(:input) { { "action" => "remove", "task" => "email" } }

      it 'removes tasks with case-insensitive matching' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Removed 1 task(s) matching 'email'.")
        
        tasks = JSON.parse(Setting.get("heartbeat_tasks"))
        expect(tasks.size).to eq(1)
        expect(tasks.first["task"]).to eq("review calendar events")
      end
    end
  end

  describe 'private methods' do
    describe '#current_tasks' do
      context 'with valid JSON' do
        before do
          Setting.set("heartbeat_tasks", [{"task" => "test"}].to_json)
        end

        it 'returns parsed tasks' do
          tasks = executor.send(:current_tasks)
          expect(tasks).to eq([{"task" => "test"}])
        end
      end

      context 'with invalid JSON' do
        before do
          allow(Setting).to receive(:get).with("heartbeat_tasks").and_return("invalid")
        end

        it 'returns empty array' do
          tasks = executor.send(:current_tasks)
          expect(tasks).to eq([])
        end
      end
    end

    describe '#save_tasks' do
      it 'stores tasks as JSON' do
        tasks = [{"task" => "test task"}]
        executor.send(:save_tasks, tasks)
        
        stored = Setting.get("heartbeat_tasks")
        expect(JSON.parse(stored)).to eq(tasks)
      end
    end
  end
end