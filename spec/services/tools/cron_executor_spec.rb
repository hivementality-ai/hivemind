# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::CronExecutor, type: :service do
  let(:agent) { create(:agent, name: "TestAgent") }

  describe "#call" do
    describe "list action" do
      it "returns empty list when no tasks exist" do
        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("No scheduled tasks")
      end

      it "lists existing tasks with status and frequency" do
        create(:scheduled_task, agent: agent, name: "Daily Report", schedule: "0 9 * * *")
        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("Daily Report")
        expect(response.data[:output]).to include("Daily at 09:00")
      end

      it "shows enabled status for active tasks" do
        create(:scheduled_task, agent: agent, enabled: true)
        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.data[:output]).to include("✅")
      end

      it "shows disabled status for inactive tasks" do
        create(:scheduled_task, agent: agent, enabled: false)
        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.data[:output]).to include("⏸️")
      end
    end

    describe "create action with confirmation (two-stage)" do
      it "returns pending_confirmation status with token" do
        input = {
          "action" => "create",
          "name" => "Blog Post Auto",
          "schedule" => "0 9 * * 1",
          "job_class" => "BlogPostJob",
          "job_params" => { "model" => "sonnet" },
          "description_hint" => "Generate weekly blog",
          "confirm" => "true"
        }
        executor = described_class.new(agent: agent, input: input)
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
        input = {
          "action" => "create",
          "name" => "",
          "schedule" => "0 9 * * *",
          "job_class" => "TestJob",
          "confirm" => "true"
        }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("name required")
      end

      it "validates schedule is required" do
        input = {
          "action" => "create",
          "name" => "Task",
          "schedule" => "",
          "job_class" => "TestJob",
          "confirm" => "true"
        }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("schedule required")
      end

      it "defaults job_class to ScheduledAgentJob when empty" do
        input = {
          "action" => "create",
          "name" => "Task",
          "schedule" => "0 9 * * *",
          "job_class" => "",
          "confirm" => "false"
        }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        task = ScheduledTask.last
        expect(task.job_class).to eq("ScheduledAgentJob")
      end

      it "accepts job_params as hash" do
        input = {
          "action" => "create",
          "name" => "Task",
          "schedule" => "0 9 * * *",
          "job_class" => "TestJob",
          "job_params" => { "key" => "value" },
          "confirm" => "true"
        }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:status]).to eq("pending_confirmation")
      end
    end

    describe "create action without confirmation (legacy)" do
      it "creates task directly when confirm is false" do
        input = {
          "action" => "create",
          "name" => "Direct Task",
          "schedule" => "0 9 * * *",
          "job_class" => "DirectJob",
          "job_params" => { "model" => "haiku" },
          "confirm" => "false"
        }
        executor = described_class.new(agent: agent, input: input)
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
        input = { "action" => "confirm_create", "confirmation_id" => "" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("confirmation_id required")
      end

      it "returns error when confirmation expired" do
        input = { "action" => "confirm_create", "confirmation_id" => "invalid_token" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
      end
    end

    describe "delete action" do
      it "deletes a task" do
        task = create(:scheduled_task, agent: agent)
        input = { "action" => "delete", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("Deleted task")
        expect(ScheduledTask.exists?(task.id)).to be false
      end

      it "validates task_id is required" do
        input = { "action" => "delete", "task_id" => "" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("task_id required")
      end

      it "prevents deletion of tasks owned by other agents" do
        other_agent = create(:agent)
        task = create(:scheduled_task, agent: other_agent)
        input = { "action" => "delete", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("do not own this task")
        expect(ScheduledTask.exists?(task.id)).to be true
      end
    end

    describe "run action" do
      it "validates task_id is required" do
        input = { "action" => "run", "task_id" => "" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("task_id required")
      end

      it "prevents running tasks owned by other agents" do
        other_agent = create(:agent)
        task = create(:scheduled_task, agent: other_agent)
        input = { "action" => "run", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("do not own this task")
      end

      it "executes a task with valid job class" do
        task = create(:scheduled_task, agent: agent, job_class: "ScheduledAgentJob")
        input = { "action" => "run", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("Executed")
      end

      it "returns error when job class doesn't exist" do
        task = create(:scheduled_task, agent: agent, job_class: "NonExistentJob")
        input = { "action" => "run", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("Unknown or disallowed job class")
      end
    end

    describe "unknown action" do
      it "returns error for unknown action" do
        input = { "action" => "unknown_action" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("Unknown cron action")
      end
    end
  end
end
