# frozen_string_literal: true

require "rails_helper"

RSpec.describe StuckTurnSweepJob, type: :job do
  let(:session) { create(:session, transcript: [], last_activity_at: 1.minute.ago) }
  let(:flag_key) { "#{ChatStreamJob::PROCESSING_KEY_PREFIX}#{session.id}" }
  let(:lock_key) { "#{ChatStreamJob::LOCK_KEY_PREFIX}#{session.id}" }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    Redis.current.del(flag_key, lock_key)
  end

  after { Redis.current.del(flag_key, lock_key) }

  it "clears a processing flag with no lock and posts an interruption message" do
    Redis.current.setex(flag_key, ChatStreamJob::PROCESSING_TTL, "1")

    expect(described_class.perform_now).to eq(1)

    expect(Redis.current.get(flag_key)).to be_nil
    last = session.reload.transcript.last
    expect(last["role"]).to eq("assistant")
    expect(last["content"]).to eq(described_class::INTERRUPTED_MESSAGE)
    expect(ActionCable.server).to have_received(:broadcast).with("session_#{session.id}", { type: "processing", active: false })
  end

  it "leaves a processing flag alone while its lock is held, however old the flag is" do
    Redis.current.setex(flag_key, 5, "1")
    Redis.current.set(lock_key, "live-worker", ex: ChatStreamJob::LOCK_TTL)
    session.update_columns(last_activity_at: 3.hours.ago)

    expect(described_class.perform_now).to eq(0)

    expect(Redis.current.get(flag_key)).to eq("1")
    expect(session.reload.transcript).to be_empty
  end
end
