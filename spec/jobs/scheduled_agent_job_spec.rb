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

  describe "#perform with a precheck URL" do
    let(:feed_url) { "https://example.com/feed.xml" }
    let(:feed) do
      <<~XML
        <rss version="2.0"><channel>
          <item><title>First post</title><link>https://example.com/1</link><guid>g1</guid></item>
        </channel></rss>
      XML
    end
    let(:watched) { create(:scheduled_task, agent: agent, job_params: { "prompt" => "Summarize" }, precheck_url: feed_url) }

    it "skips the run with no model call when the feed has nothing new" do
      watched.update!(precheck_state: { "ids" => [ "g1" ] })
      stub_request(:get, feed_url).to_return(status: 200, body: feed)

      expect { described_class.perform_now(watched.id) }.not_to change(Session, :count)
      expect(ChatStreamJob).not_to have_been_enqueued

      watched.reload
      expect(watched.last_check_result).to eq("unchanged")
      expect(watched.last_checked_at).to be_present
      expect(watched.last_run_at).to be_nil
    end

    it "runs and passes new items into the prompt" do
      watched.update!(precheck_state: { "ids" => [ "g0" ] })
      stub_request(:get, feed_url).to_return(status: 200, body: feed)

      described_class.perform_now(watched.id)

      expect(ChatStreamJob).to have_been_enqueued.with(
        anything, a_string_including("Summarize", "First post", "https://example.com/1")
      )
      expect(watched.reload.precheck_state["ids"]).to include("g0", "g1")
    end

    it "skips an unchanged page and runs a changed one" do
      page_url = "https://example.com/page"
      watched.update!(precheck_url: page_url)
      stub_request(:get, page_url).to_return(status: 200, body: "<html><body>v1</body></html>")
      described_class.perform_now(watched.id)
      expect(ChatStreamJob).to have_been_enqueued.once

      described_class.perform_now(watched.id)
      expect(ChatStreamJob).to have_been_enqueued.once

      stub_request(:get, page_url).to_return(status: 200, body: "<html><body>v2</body></html>")
      described_class.perform_now(watched.id)
      expect(ChatStreamJob).to have_been_enqueued.twice
    end

    it "runs the task as usual when the fetch fails" do
      stub_request(:get, feed_url).to_return(status: 500)

      expect { described_class.perform_now(watched.id) }.to have_enqueued_job(ChatStreamJob)
      expect(watched.reload.last_check_result).to eq("failed")
    end

    it "runs the task as usual when the fetch times out" do
      stub_request(:get, feed_url).to_timeout

      expect { described_class.perform_now(watched.id) }.to have_enqueued_job(ChatStreamJob)
    end

    it "treats an oversized response as a failed fetch" do
      stub_request(:get, feed_url).to_return(status: 200, body: "x" * (ScheduledTasks::Precheck::MAX_BYTES + 1))

      expect { described_class.perform_now(watched.id) }.to have_enqueued_job(ChatStreamJob)
      expect(watched.reload.last_check_result).to eq("failed")
    end

    it "makes no request and runs as before without a precheck URL" do
      expect { described_class.perform_now(task.id) }.to have_enqueued_job(ChatStreamJob)
      expect(task.reload.last_check_result).to be_nil
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end
end
