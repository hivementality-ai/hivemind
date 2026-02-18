# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::CronExecutor, type: :service do
  let(:agent) { create(:agent, name: "TestAgent") }
  let(:executor) { described_class.new(agent: agent, input: {}) }

  describe "#call" do
    describe "list action" do
      it "returns empty list when no tasks exist" do
        executor.input = { "action" => "list" }
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("No scheduled tasks")
      end

      it "lists existing tasks with status and frequency" do
        create(:scheduled_task, agent: agent, name: "Daily Report", schedule: "0 9 * * *")
        executor.input = { "action" => "list" }
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("Daily Report")
        expect(response.data[:output]).to include("Daily at 09:00")
      end

      it "shows enabled status for active tasks" do
        create(:scheduled_task, agent: agent, enabled: true)
        executor.input = { "action" => "list" }
        response = executor.call

        expect(response.data[:output]).to include("✅")
      end

      it "shows disabled status for inactive tasks" do
        create(:scheduled_task, agent: agent, enabled: false)
        executor.input = { "action" => "list" }
        response = executor.call

        expect(response.data[:output]).to include("⏸️")
      end
    end

    describe "create action with confirmation (two-stage)" do
      it "returns pending_confirmation status with token" do
        executor.input = {
          "action" => "create",
          "name" => "Blog Post Auto",
          "schedule" => "0 9 * * 1",
          "job_class" => "BlogPostJob",
          "job_params" => { "model" => "sonnet" },
          "description_hint" => "Generate weekly blog",
          "confirm" => "true"
        }

        response = executor.call
        expect(response.success?).to be true
        expect(response.data[:status]).to eq("pending_confirmation")
        expect(response.data[:confirmation_id]).to be_present
        expect(response.data[:explanation]).to include(
          frequency: "Every Monday at 09:00",
          agent: "TestAgent"
        )
      end

      it "validates name is required" do
        executor.input = {
          "action" => "create",
          "name" => "",
          "schedule" => "0 9 * * *",
          "job_class" => "TestJob",
          "confirm" => "true"
        }

        response = executor.call
        expect(response.success?).to be false
        expect(response.error).to include("name required")
      end

      it "validates schedule is required" do
        executor.input = {
          "action" => "create",
          "name" => "Task",
          "schedule" => "",
          "job_class" => "TestJob",
          "confirm" => "true"
        }

        response = executor.call
        expect(response.success?).to be false
        expect(response.error).to include("schedule required")
      end

      it "validates job_class is required" do
        executor.input = {
          "action" => "create",
          "name" => "Task",
          "schedule" => "0 9 * * *",
          "job_class" => "",
          "confirm" => "true"
        }

        response = executor.call
        expect(response.success?).to be false
        expect(response.error).to include("job_class required")
      end

      it "accepts job_params as hash" do
        executor.input = {
          "action" => "create",
          "name" => "Task",
          "schedule" => "0 9 * * *",
          "job_class" => "TestJob",
          "job_params" => { "key" => "value" },
          "confirm" => "true"
        }

        response = executor.call
        expect(response.success?).to be true
        expect(response.data[:status]).to eq("pending_confirmation")
      end
    end

    describe "create action without confirmation (legacy)" do
      it "creates task directly when confirm is false" do
        executor.input = {
          "action" => "create",
          "name" => "Direct Task",
          "schedule" => "0 9 * * *",
          "job_class" => "DirectJob",
          "job_params" => { "model" => "haiku" },
          "confirm" => "false"
        }

        response = executor.call
        expect(response.success?).to be true
        expect(response.data[:status]).to eq("created")
        expect(response.data[:task_id]).to be_present

        # Verify task exists in database
        task = ScheduledTask.find(response.data[:task_id])
        expect(task.name).to eq("Direct Task")
        expect(task.job_class).to eq("DirectJob")
        expect(task.job_params).to eq({ "model" => "haiku" })
      end
    end

    describe "confirm_create action" do
      it "returns error when confirmation_id is missing" do
        executor.input = { "action" => "confirm_create", "confirmation_id" => "" }
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("confirmation_id required")
      end

      it "returns error when confirmation expired" do
        executor.input = { "action" => "confirm_create", "confirmation_id" => "invalid_token" }
        response = executor.call

        expect(response.success?).to be false
      end
    end

    describe "delete action" do
      it "deletes a task" do
        task = create(:scheduled_task, agent: agent)
        executor.input = { "action" => "delete", "task_id" => task.id.to_s }

        response = executor.call
        expect(response.success?).to be true
        expect(response.data[:output]).to include("Deleted task")
        expect(ScheduledTask.exists?(task.id)).to be false
      end

      it "validates task_id is required" do
        executor.input = { "action" => "delete", "task_id" => "" }
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("task_id required")
      end

      it "prevents deletion of tasks owned by other agents" do
        other_agent = create(:agent)
        task = create(:scheduled_task, agent: other_agent)
        executor.input = { "action" => "delete", "task_id" => task.id.to_s }

        response = executor.call
        expect(response.success?).to be false
        expect(response.error).to include("do not own this task")
        expect(ScheduledTask.exists?(task.id)).to be true
      end
    end

    describe "run action" do
      it "validates task_id is required" do
        executor.input = { "action" => "run", "task_id" => "" }
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("task_id required")
      end

      it "prevents running tasks owned by other agents" do
        other_agent = create(:agent)
        task = create(:scheduled_task, agent: other_agent)
        executor.input = { "action" => "run", "task_id" => task.id.to_s }

        response = executor.call
        expect(response.success?).to be false
        expect(response.error).to include("do not own this task")
      end

      it "executes a task with valid job class" do
        # Create a mock job class
        stub_const("TestExecutableJob", Class.new do
          def self.perform_now(**params)
            # Mock job execution
          end
        end)

        task = create(:scheduled_task, agent: agent, job_class: "TestExecutableJob")
        executor.input = { "action" => "run", "task_id" => task.id.to_s }

        response = executor.call
        expect(response.success?).to be true
        expect(response.data[:output]).to include("Executed")
      end

      it "returns error when job class doesn't exist" do
        task = create(:scheduled_task, agent: agent, job_class: "NonExistentJob")
        executor.input = { "action" => "run", "task_id" => task.id.to_s }

        response = executor.call
        expect(response.success?).to be false
        expect(response.error).to include("Job class not found")
      end
    end

    describe "unknown action" do
      it "returns error for unknown action" do
        executor.input = { "action" => "unknown_action" }
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("Unknown cron action")
      end
    end
  end
end
