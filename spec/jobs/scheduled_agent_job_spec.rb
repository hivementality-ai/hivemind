# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledAgentJob, type: :job do
  let(:agent) { create(:agent) }
  let(:task) do
    create(:scheduled_task,
      agent: agent,
      name: "Daily Briefing",
      schedule: "0 9 * * *",
      job_params: { "prompt" => "Give me a status update" },
      enabled: true
    )
  end

  describe "#perform" do
    it "creates a session with session_key and metadata" do
      expect {
        described_class.perform_now(task.id)
      }.to change(Session, :count).by(1)

      session = Session.last
      expect(session.session_key).to start_with("scheduled-#{task.id}-")
      expect(session.title).to eq("Scheduled: Daily Briefing")
      expect(session.metadata["type"]).to eq("scheduled")
      expect(session.metadata["scheduled_task_id"]).to eq(task.id)
    end

    it "enqueues ChatStreamJob with session_id and prompt" do
      expect {
        described_class.perform_now(task.id)
      }.to have_enqueued_job(ChatStreamJob)
    end

    it "updates last_run_at on the task" do
      described_class.perform_now(task.id)
      task.reload
      expect(task.last_run_at).to be_present
    end

    it "calculates next_run_at from cron schedule" do
      described_class.perform_now(task.id)
      task.reload
      expect(task.next_run_at).to be_present
      expect(task.next_run_at).to be > Time.current
    end

    it "uses task description as fallback prompt" do
      task.update!(job_params: {}, description: "Run the daily check")

      expect {
        described_class.perform_now(task.id)
      }.to have_enqueued_job(ChatStreamJob)
    end

    it "skips disabled tasks" do
      task.update!(enabled: false)

      expect {
        described_class.perform_now(task.id)
      }.not_to change(Session, :count)
    end

    it "skips nonexistent tasks" do
      expect {
        described_class.perform_now(999999)
      }.not_to change(Session, :count)
    end

    it "records last_error_at on failure" do
      # Stub at the agent level so session creation fails
      allow_any_instance_of(Agent).to receive_message_chain(:sessions, :create!).and_raise(StandardError, "boom")

      described_class.perform_now(task.id)
      task.reload
      expect(task.last_error_at).to be_present
    end
  end
end
