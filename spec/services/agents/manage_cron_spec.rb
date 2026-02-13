# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::ManageCron do
  describe '.call' do
    let(:agent) { create(:agent) }

    before do
      # Mock Sidekiq::Cron::Job methods
      allow(Sidekiq::Cron::Job).to receive(:create)
      allow(Sidekiq::Cron::Job).to receive(:destroy)
      # Mock AuditLog creation
      allow(AuditLog).to receive(:create)
    end

    describe 'create action' do
      let(:schedule) { "0 9 * * *" } # Daily at 9 AM
      let(:name) { "Daily Report" }
      let(:job_params) { { report_type: "summary" } }

      context 'with valid parameters' do
        it 'creates a new scheduled task' do
          result = described_class.call(
            action: "create",
            agent: agent,
            schedule: schedule,
            name: name,
            job_params: job_params
          )

          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true

          task = result.data[:task]
          expect(task).to be_a(ScheduledTask)
          expect(task).to be_persisted
          expect(task.agent_id).to eq(agent.id)
          expect(task.name).to eq(name)
          expect(task.schedule).to eq(schedule)
          expect(task.job_class).to eq("AgentScheduledJob")
          expect(task.job_params).to eq(job_params.stringify_keys)
          expect(task.enabled).to be true
        end

        it 'syncs the task to Sidekiq' do
          result = described_class.call(
            action: "create",
            agent: agent,
            schedule: schedule,
            name: name
          )

          task = result.data[:task]
          expect(Sidekiq::Cron::Job).to have_received(:create).with(
            name: "scheduled_task_#{task.id}",
            cron: schedule,
            class: "AgentScheduledJob",
            args: [task.id]
          )
        end

        it 'creates audit log entry' do
          described_class.call(
            action: "create",
            agent: agent,
            schedule: schedule,
            name: name
          )

          expect(AuditLog).to have_received(:create).with(
            actor_type: "Agent",
            actor_id: agent.id,
            action: "cron_create",
            resource_type: "ScheduledTask",
            resource_id: be_a(Integer),
            metadata: {
              action: "create",
              task_id: nil,
              schedule: schedule
            }
          )
        end

        it 'handles disabled tasks' do
          result = described_class.call(
            action: "create",
            agent: agent,
            schedule: schedule,
            name: name,
            enabled: false
          )

          expect(result.success?).to be true
          expect(result.data[:task].enabled).to be false
          expect(Sidekiq::Cron::Job).not_to have_received(:create)
        end
      end

      context 'with missing required parameters' do
        it 'fails when schedule is missing' do
          result = described_class.call(
            action: "create",
            agent: agent,
            name: name
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Schedule is required")
        end

        it 'fails when name is missing' do
          result = described_class.call(
            action: "create",
            agent: agent,
            schedule: schedule
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Name is required")
        end
      end

      context 'when task creation fails' do
        before do
          allow(ScheduledTask).to receive(:create).and_return(
            double(persisted?: false, errors: double(full_messages: ["Name can't be blank"]))
          )
        end

        it 'returns failure with validation errors' do
          result = described_class.call(
            action: "create",
            agent: agent,
            schedule: schedule,
            name: name
          )

          expect(result.success?).to be false
          expect(result.error).to eq(["Name can't be blank"])
        end
      end
    end

    describe 'update action' do
      let!(:task) { create(:scheduled_task, agent: agent, name: "Old Name", schedule: "0 8 * * *") }
      let(:new_schedule) { "0 10 * * *" }
      let(:new_name) { "New Name" }

      context 'with valid parameters' do
        it 'updates the scheduled task' do
          result = described_class.call(
            action: "update",
            agent: agent,
            task_id: task.id,
            schedule: new_schedule,
            name: new_name
          )

          expect(result.success?).to be true
          task.reload
          expect(task.name).to eq(new_name)
          expect(task.schedule).to eq(new_schedule)
        end

        it 'syncs updated task to Sidekiq' do
          described_class.call(
            action: "update",
            agent: agent,
            task_id: task.id,
            schedule: new_schedule
          )

          expect(Sidekiq::Cron::Job).to have_received(:create).with(
            name: "scheduled_task_#{task.id}",
            cron: new_schedule,
            class: task.job_class,
            args: [task.id]
          )
        end

        it 'removes from Sidekiq when disabled' do
          described_class.call(
            action: "update",
            agent: agent,
            task_id: task.id,
            enabled: false
          )

          expect(Sidekiq::Cron::Job).to have_received(:destroy).with("scheduled_task_#{task.id}")
        end
      end

      context 'with invalid parameters' do
        it 'fails when task_id is missing' do
          result = described_class.call(
            action: "update",
            agent: agent,
            schedule: new_schedule
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Task ID is required")
        end

        it 'fails when task does not exist' do
          result = described_class.call(
            action: "update",
            agent: agent,
            task_id: 99999,
            schedule: new_schedule
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Task not found")
        end

        it 'fails when task belongs to different agent' do
          other_agent = create(:agent)
          other_task = create(:scheduled_task, agent: other_agent)

          result = described_class.call(
            action: "update",
            agent: agent,
            task_id: other_task.id,
            schedule: new_schedule
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Task not found")
        end
      end

      context 'when task update fails' do
        before do
          allow(ScheduledTask).to receive(:find_by).and_return(
            double(update: false, errors: double(full_messages: ["Schedule is invalid"]))
          )
        end

        it 'returns failure with validation errors' do
          result = described_class.call(
            action: "update",
            agent: agent,
            task_id: task.id,
            schedule: new_schedule
          )

          expect(result.success?).to be false
          expect(result.error).to eq(["Schedule is invalid"])
        end
      end
    end

    describe 'delete action' do
      let!(:task) { create(:scheduled_task, agent: agent) }

      context 'with valid task_id' do
        it 'deletes the scheduled task' do
          expect {
            described_class.call(
              action: "delete",
              agent: agent,
              task_id: task.id
            )
          }.to change(ScheduledTask, :count).by(-1)
        end

        it 'removes task from Sidekiq' do
          described_class.call(
            action: "delete",
            agent: agent,
            task_id: task.id
          )

          expect(Sidekiq::Cron::Job).to have_received(:destroy).with("scheduled_task_#{task.id}")
        end

        it 'returns success with deletion confirmation' do
          result = described_class.call(
            action: "delete",
            agent: agent,
            task_id: task.id
          )

          expect(result.success?).to be true
          expect(result.data[:task_id]).to eq(task.id)
          expect(result.data[:deleted]).to be true
        end
      end

      context 'with invalid parameters' do
        it 'fails when task_id is missing' do
          result = described_class.call(
            action: "delete",
            agent: agent
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Task ID is required")
        end

        it 'fails when task does not exist' do
          result = described_class.call(
            action: "delete",
            agent: agent,
            task_id: 99999
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Task not found")
        end
      end
    end

    describe 'list action' do
      let!(:task1) { create(:scheduled_task, agent: agent, name: "Task 1") }
      let!(:task2) { create(:scheduled_task, agent: agent, name: "Task 2") }
      let!(:other_agent_task) { create(:scheduled_task, name: "Other Task") }

      it 'returns all tasks for the agent' do
        result = described_class.call(
          action: "list",
          agent: agent
        )

        expect(result.success?).to be true
        tasks_data = result.data[:tasks]
        expect(tasks_data).to be_an(Array)
        expect(tasks_data.length).to eq(2)
        
        task_names = tasks_data.map { |t| t["name"] }
        expect(task_names).to include("Task 1", "Task 2")
        expect(task_names).not_to include("Other Task")
      end

      it 'orders tasks by creation date descending' do
        result = described_class.call(
          action: "list",
          agent: agent
        )

        tasks_data = result.data[:tasks]
        expect(tasks_data.first["name"]).to eq("Task 2") # Created later
      end

      it 'returns empty array when no tasks exist' do
        ScheduledTask.where(agent: agent).destroy_all

        result = described_class.call(
          action: "list",
          agent: agent
        )

        expect(result.success?).to be true
        expect(result.data[:tasks]).to eq([])
      end
    end

    describe 'invalid action' do
      it 'fails with invalid action' do
        result = described_class.call(
          action: "invalid",
          agent: agent
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Invalid action: invalid")
      end
    end

    describe 'exception handling' do
      before do
        allow(ScheduledTask).to receive(:create).and_raise(StandardError, "Database connection lost")
      end

      it 'returns failure with error message' do
        result = described_class.call(
          action: "create",
          agent: agent,
          schedule: "0 9 * * *",
          name: "Test Task"
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Cron management failed: Database connection lost")
      end
    end
  end
end