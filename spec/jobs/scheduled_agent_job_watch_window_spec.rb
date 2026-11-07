# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledAgentJob, "quiet hours and digest", type: :job do
  let(:feed_url) { "https://example.com/feed.xml" }
  let(:watched) do
    create(:scheduled_task, agent: create(:agent), job_params: { "prompt" => "Summarize" }, precheck_url: feed_url,
                            quiet_start_hour: 22, quiet_end_hour: 7)
  end

  def feed_with(*ids)
    items = ids.map { |id| "<item><title>Post #{id}</title><link>https://example.com/#{id}</link><guid>#{id}</guid></item>" }
    "<rss version=\"2.0\"><channel>#{items.join}</channel></rss>"
  end

  def check_at(task, hour, body, day: 8)
    stub_request(:get, feed_url).to_return(status: 200, body: body)
    travel_to(Time.zone.local(2026, 11, day, hour, 5)) { described_class.perform_now(task.id) }
  end

  it "holds new items during quiet hours without running" do
    expect { check_at(watched, 23, feed_with("a", "b")) }.not_to change(Session, :count)

    watched.reload
    expect(watched.held_items.map { |i| i["id"] }).to eq(%w[a b])
    expect(watched.last_check_result).to eq("held")
    expect(watched.precheck_state["ids"]).to include("a", "b")
    expect(watched.last_run_at).to be_nil
  end

  it "does not lose or repeat items across held checks, then releases once when quiet hours end" do
    check_at(watched, 23, feed_with("a"))
    check_at(watched, 2, feed_with("a", "b"))
    expect(watched.reload.held_items.map { |i| i["id"] }).to eq(%w[a b])
    expect(ChatStreamJob).not_to have_been_enqueued

    check_at(watched, 7, feed_with("a", "b"), day: 9)
    expect(ChatStreamJob).to have_been_enqueued.once.with(
      anything, a_string_including("New since the last check:", "Post a", "Post b")
    )
    expect(watched.reload.held_items).to be_empty

    check_at(watched, 8, feed_with("a", "b"), day: 9)
    expect(ChatStreamJob).to have_been_enqueued.once
  end

  it "runs a new item straight away outside quiet hours and folds in anything held" do
    check_at(watched, 23, feed_with("a"))
    check_at(watched, 9, feed_with("a", "b"), day: 9)

    expect(ChatStreamJob).to have_been_enqueued.once.with(anything, a_string_including("Post a", "Post b"))
  end

  it "still skips quietly during quiet hours when nothing is new" do
    watched.update!(precheck_state: { "ids" => [ "a" ] })
    check_at(watched, 23, feed_with("a"))

    expect(watched.reload.last_check_result).to eq("unchanged")
    expect(ChatStreamJob).not_to have_been_enqueued
  end

  it "holds a changed page and releases it after quiet hours" do
    watched.update!(precheck_url: "https://example.com/page")
    stub_request(:get, "https://example.com/page").to_return(status: 200, body: "<html>v1</html>")
    travel_to(Time.zone.local(2026, 11, 8, 23, 5)) { described_class.perform_now(watched.id) }
    expect(ChatStreamJob).not_to have_been_enqueued
    expect(watched.reload.holding?).to be(true)

    travel_to(Time.zone.local(2026, 11, 9, 8, 5)) { described_class.perform_now(watched.id) }
    expect(ChatStreamJob).to have_been_enqueued.once
    expect(watched.reload.holding?).to be(false)
  end

  it "runs as usual during quiet hours when the fetch fails" do
    stub_request(:get, feed_url).to_return(status: 500)

    travel_to(Time.zone.local(2026, 11, 8, 23, 5)) { described_class.perform_now(watched.id) }

    expect(ChatStreamJob).to have_been_enqueued.once
    expect(watched.reload.last_check_result).to eq("failed")
  end

  context "with a daily digest at 7" do
    before { watched.update!(quiet_start_hour: nil, quiet_end_hour: nil, digest_hour: 7) }

    it "gathers items all day and runs once at digest time" do
      check_at(watched, 10, feed_with("a"))
      check_at(watched, 15, feed_with("a", "b"))
      check_at(watched, 20, feed_with("a", "b", "c"))
      expect(ChatStreamJob).not_to have_been_enqueued
      expect(watched.reload.held_items.map { |i| i["id"] }).to eq(%w[a b c])

      check_at(watched, 7, feed_with("a", "b", "c"), day: 9)
      expect(ChatStreamJob).to have_been_enqueued.once.with(
        anything, a_string_including("Post a", "Post b", "Post c")
      )

      check_at(watched, 8, feed_with("a", "b", "c", "d"), day: 9)
      expect(ChatStreamJob).to have_been_enqueued.once
      expect(watched.reload.held_items.map { |i| i["id"] }).to eq(%w[d])
    end

    it "says how many were held back beyond the cap" do
      ids = (1..14).map { |i| "p#{i}" }
      check_at(watched, 10, feed_with(*ids.first(7)))
      check_at(watched, 12, feed_with(*ids))
      check_at(watched, 7, feed_with(*ids), day: 9)

      expect(ChatStreamJob).to have_been_enqueued.with(anything, a_string_including("and 4 more"))
    end

    it "does not run when nothing came in" do
      watched.update!(precheck_state: { "ids" => [ "a" ] })
      check_at(watched, 7, feed_with("a"), day: 9)

      expect(ChatStreamJob).not_to have_been_enqueued
      expect(watched.reload.last_check_result).to eq("unchanged")
    end
  end
end
