# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledScriptJob, type: :job do
  let(:agent) { create(:agent, name: "TestAgent") }

  describe "#perform" do
    it "does nothing if task not found" do
      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it "does nothing if task is disabled" do
      task = create(:scheduled_task, agent: agent, enabled: false, job_class: "ScheduledScriptJob",
        job_params: { "script_path" => "/workspace/scripts/test.sh" })

      expect_any_instance_of(described_class).not_to receive(:execute_script)
      described_class.new.perform(task.id)
    end

    it "records error when no script_path is configured" do
      task = create(:scheduled_task, agent: agent, enabled: true, job_class: "ScheduledScriptJob",
        job_params: {})

      described_class.new.perform(task.id)

      task.reload
      expect(task.last_error_at).to be_present
      expect(task.last_error_message).to include("No script_path configured")
    end

    it "executes the script and updates last_run_at on success" do
      task = create(:scheduled_task, agent: agent, enabled: true, job_class: "ScheduledScriptJob",
        job_params: { "script_path" => "/workspace/scripts/report.py" })

      allow_any_instance_of(described_class).to receive(:execute_script)
        .with("/workspace/scripts/report.py")
        .and_return([ "Report generated\n", 0 ])

      described_class.new.perform(task.id)

      task.reload
      expect(task.last_run_at).to be_present
      expect(task.last_error_at).to be_nil
    end

    it "creates a session for the run" do
      task = create(:scheduled_task, agent: agent, enabled: true, job_class: "ScheduledScriptJob",
        job_params: { "script_path" => "/workspace/scripts/report.py" })

      allow_any_instance_of(described_class).to receive(:execute_script)
        .and_return([ "Done\n", 0 ])

      expect { described_class.new.perform(task.id) }.to change(Session, :count).by(1)

      session = Session.last
      expect(session.title).to include("Script:")
      expect(session.session_type).to eq("scheduled")
    end

    it "records error info on script failure" do
      task = create(:scheduled_task, agent: agent, enabled: true, job_class: "ScheduledScriptJob",
        job_params: { "script_path" => "/workspace/scripts/bad.sh" })

      allow_any_instance_of(described_class).to receive(:execute_script)
        .with("/workspace/scripts/bad.sh")
        .and_return([ "Error: file not found", 1 ])

      described_class.new.perform(task.id)

      task.reload
      expect(task.last_run_at).to be_present
      expect(task.last_error_at).to be_present
      expect(task.last_error_message).to include("Error: file not found")
    end

    it "stores output in session metadata" do
      task = create(:scheduled_task, agent: agent, enabled: true, job_class: "ScheduledScriptJob",
        job_params: { "script_path" => "/workspace/scripts/report.py" })

      allow_any_instance_of(described_class).to receive(:execute_script)
        .and_return([ "Report output here\n", 0 ])

      described_class.new.perform(task.id)

      session = Session.last
      expect(session.metadata["output"]).to include("Report output here")
      expect(session.metadata["exit_code"]).to eq(0)
      expect(session.metadata["status"]).to eq("success")
    end

    it "handles unexpected exceptions gracefully" do
      task = create(:scheduled_task, agent: agent, enabled: true, job_class: "ScheduledScriptJob",
        job_params: { "script_path" => "/workspace/scripts/report.py" })

      allow_any_instance_of(described_class).to receive(:execute_script)
        .and_raise(StandardError, "Docker is down")

      described_class.new.perform(task.id)

      task.reload
      expect(task.last_error_at).to be_present
      expect(task.last_error_message).to include("Docker is down")
    end
  end
end
