# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CronScriptExecutor, type: :service do
  let(:agent) { create(:agent, name: "TestAgent") }

  describe "#call" do
    describe "list action" do
      it "returns empty list when no script tasks exist" do
        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("No scheduled scripts")
      end

      it "lists existing script tasks with status, frequency, and script path" do
        create(:scheduled_task,
          agent: agent,
          name: "Daily Report",
          schedule: "0 9 * * *",
          job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/scripts/report.py" })

        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("Daily Report")
        expect(response.data[:output]).to include("/workspace/scripts/report.py")
      end

      it "only lists ScheduledScriptJob tasks" do
        create(:scheduled_task, agent: agent, name: "Prompt Task", job_class: "ScheduledAgentJob")
        create(:scheduled_task, agent: agent, name: "Script Task", job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/scripts/test.sh" })

        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.data[:output]).to include("Script Task")
        expect(response.data[:output]).not_to include("Prompt Task")
      end

      it "only lists tasks owned by the agent" do
        other_agent = create(:agent)
        create(:scheduled_task, agent: other_agent, name: "Other Script", job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/scripts/other.sh" })

        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.data[:output]).to include("No scheduled scripts")
      end

      it "shows enabled status for active tasks" do
        create(:scheduled_task, agent: agent, enabled: true, job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/scripts/test.sh" })

        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.data[:output]).to include("✅")
      end

      it "shows disabled status for inactive tasks" do
        create(:scheduled_task, agent: agent, enabled: false, job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/scripts/test.sh" })

        executor = described_class.new(agent: agent, input: { "action" => "list" })
        response = executor.call

        expect(response.data[:output]).to include("⏸️")
      end
    end

    describe "create action" do
      before do
        allow_any_instance_of(described_class).to receive(:script_exists?).and_return(true)
      end

      it "validates name is required" do
        input = { "action" => "create", "name" => "", "schedule" => "0 9 * * *", "script_path" => "/workspace/test.py" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("name required")
      end

      it "validates schedule is required" do
        input = { "action" => "create", "name" => "Task", "schedule" => "", "script_path" => "/workspace/test.py" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("schedule required")
      end

      it "validates script_path is required" do
        input = { "action" => "create", "name" => "Task", "schedule" => "0 9 * * *", "script_path" => "" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("script_path required")
      end

      it "validates script_path must be under /workspace/" do
        input = { "action" => "create", "name" => "Task", "schedule" => "0 9 * * *", "script_path" => "/etc/passwd" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("must be under /workspace/")
      end

      it "validates script file exists" do
        allow_any_instance_of(described_class).to receive(:script_exists?).and_return(false)

        input = { "action" => "create", "name" => "Task", "schedule" => "0 9 * * *", "script_path" => "/workspace/missing.py" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("Script not found")
      end

      it "creates task directly when confirm is false" do
        input = {
          "action" => "create",
          "name" => "Daily Script",
          "schedule" => "0 9 * * *",
          "script_path" => "/workspace/scripts/report.py",
          "confirm" => "false"
        }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:status]).to eq("created")
        expect(response.data[:task_id]).to be_present

        task = ScheduledTask.find(response.data[:task_id])
        expect(task.name).to eq("Daily Script")
        expect(task.job_class).to eq("ScheduledScriptJob")
        expect(task.job_params).to eq({ "script_path" => "/workspace/scripts/report.py" })
      end

      it "returns pending_confirmation with confirm flow" do
        input = {
          "action" => "create",
          "name" => "Daily Script",
          "schedule" => "0 9 * * *",
          "script_path" => "/workspace/scripts/report.py",
          "confirm" => "true"
        }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:status]).to eq("pending_confirmation")
        expect(response.data[:confirmation_id]).to be_present
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

      it "returns error when confirmation is invalid" do
        input = { "action" => "confirm_create", "confirmation_id" => "invalid_token" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
      end
    end

    describe "delete action" do
      it "deletes a script task" do
        task = create(:scheduled_task, agent: agent, job_class: "ScheduledScriptJob")
        input = { "action" => "delete", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("Deleted script task")
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
        task = create(:scheduled_task, agent: other_agent, job_class: "ScheduledScriptJob")
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
        task = create(:scheduled_task, agent: other_agent, job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/test.sh" })
        input = { "action" => "run", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("do not own this task")
      end

      it "returns error when no script_path configured" do
        task = create(:scheduled_task, agent: agent, job_class: "ScheduledScriptJob", job_params: {})
        input = { "action" => "run", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("No script_path configured")
      end

      it "executes a script task successfully" do
        task = create(:scheduled_task, agent: agent, job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/scripts/test.sh" })

        allow_any_instance_of(described_class).to receive(:execute_script)
          .with("/workspace/scripts/test.sh")
          .and_return(["Hello from script\n", 0])

        input = { "action" => "run", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("Executed")
        expect(response.data[:output]).to include("Hello from script")
        expect(task.reload.last_run_at).to be_present
      end

      it "handles script failure" do
        task = create(:scheduled_task, agent: agent, job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/scripts/bad.sh" })

        allow_any_instance_of(described_class).to receive(:execute_script)
          .with("/workspace/scripts/bad.sh")
          .and_return(["Error: something went wrong", 1])

        input = { "action" => "run", "task_id" => task.id.to_s }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("Script exited with code 1")
        expect(task.reload.last_error_at).to be_present
      end
    end

    describe "update_script action" do
      before do
        allow_any_instance_of(described_class).to receive(:script_exists?).and_return(true)
      end

      it "updates the script_path for a task" do
        task = create(:scheduled_task, agent: agent, job_class: "ScheduledScriptJob",
          job_params: { "script_path" => "/workspace/scripts/old.py" })

        input = { "action" => "update_script", "task_id" => task.id.to_s, "script_path" => "/workspace/scripts/new.py" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be true
        expect(response.data[:output]).to include("Updated script path")
        expect(task.reload.job_params["script_path"]).to eq("/workspace/scripts/new.py")
      end

      it "validates task_id is required" do
        input = { "action" => "update_script", "task_id" => "", "script_path" => "/workspace/test.py" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("task_id required")
      end

      it "validates script_path is required" do
        task = create(:scheduled_task, agent: agent, job_class: "ScheduledScriptJob")
        input = { "action" => "update_script", "task_id" => task.id.to_s, "script_path" => "" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("script_path required")
      end

      it "validates script_path must be under /workspace/" do
        task = create(:scheduled_task, agent: agent, job_class: "ScheduledScriptJob")
        input = { "action" => "update_script", "task_id" => task.id.to_s, "script_path" => "/tmp/evil.sh" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("must be under /workspace/")
      end

      it "prevents updating tasks owned by other agents" do
        other_agent = create(:agent)
        task = create(:scheduled_task, agent: other_agent, job_class: "ScheduledScriptJob")
        input = { "action" => "update_script", "task_id" => task.id.to_s, "script_path" => "/workspace/test.py" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("do not own this task")
      end

      it "validates the new script file exists" do
        allow_any_instance_of(described_class).to receive(:script_exists?).and_return(false)

        task = create(:scheduled_task, agent: agent, job_class: "ScheduledScriptJob")
        input = { "action" => "update_script", "task_id" => task.id.to_s, "script_path" => "/workspace/missing.py" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("Script not found")
      end
    end

    describe "unknown action" do
      it "returns error for unknown action" do
        input = { "action" => "unknown_action" }
        executor = described_class.new(agent: agent, input: input)
        response = executor.call

        expect(response.success?).to be false
        expect(response.error).to include("Unknown cron_script action")
      end
    end
  end
end
