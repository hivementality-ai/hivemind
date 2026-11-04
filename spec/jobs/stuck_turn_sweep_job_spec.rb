# frozen_string_literal: true

require "rails_helper"

RSpec.describe StuckTurnSweepJob, type: :job do
  let(:session) { create(:session, transcript: [], last_activity_at: 1.hour.ago) }
  let(:flag_key) { "#{ChatStreamJob::PROCESSING_KEY_PREFIX}#{session.id}" }
  let(:lock_key) { "#{ChatStreamJob::LOCK_KEY_PREFIX}#{session.id}" }
  let(:stale_ttl) { ChatStreamJob::PROCESSING_TTL - ChatStreamJob::STALE_AFTER - 60 }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    Redis.current.del(flag_key, lock_key)
  end

  after { Redis.current.del(flag_key, lock_key) }

  it "clears a stale processing flag and lock and posts an interruption message" do
    Redis.current.setex(flag_key, stale_ttl, "1")
    Redis.current.set(lock_key, "dead-worker")

    expect(described_class.perform_now).to eq(1)

    expect(Redis.current.get(flag_key)).to be_nil
    expect(Redis.current.get(lock_key)).to be_nil
    last = session.reload.transcript.last
    expect(last["role"]).to eq("assistant")
    expect(last["content"]).to eq(described_class::INTERRUPTED_MESSAGE)
    expect(ActionCable.server).to have_received(:broadcast).with("session_#{session.id}", { type: "processing", active: false })
  end

  it "leaves a fresh processing flag alone" do
    Redis.current.setex(flag_key, ChatStreamJob::PROCESSING_TTL, "1")
    Redis.current.set(lock_key, "live-worker")

    expect(described_class.perform_now).to eq(0)

    expect(Redis.current.get(flag_key)).to eq("1")
    expect(Redis.current.get(lock_key)).to eq("live-worker")
    expect(session.reload.transcript).to be_empty
  end

  it "leaves an old flag alone while the session is still active" do
    session.update_columns(last_activity_at: 1.minute.ago)
    Redis.current.setex(flag_key, stale_ttl, "1")

    expect(described_class.perform_now).to eq(0)
    expect(Redis.current.get(flag_key)).to eq("1")
  end
end
