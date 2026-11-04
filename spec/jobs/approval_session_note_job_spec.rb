# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApprovalSessionNoteJob, type: :job do
  let(:session) { create(:session, session_key: "note-#{SecureRandom.hex(4)}") }
  let(:lock_key) { "#{ChatStreamJob::LOCK_KEY_PREFIX}#{session.id}" }
  let(:note) { "Approval result: Ran POST /widgets on Shop: succeeded" }

  before { Redis.current.del(lock_key) }
  after { Redis.current.del(lock_key) }

  it "writes the note and broadcasts it when no turn is running" do
    allow(ActionCable.server).to receive(:broadcast)

    described_class.perform_now(session.id, note)

    expect(session.reload.transcript.last).to include("role" => "assistant", "content" => note)
    expect(ActionCable.server).to have_received(:broadcast).with("session_#{session.id}", hash_including(type: "notice"))
    expect(Redis.current.exists?(lock_key)).to be(false)
  end

  it "appends to the transcript as it is now, not as it was when queued" do
    stale = Session.find(session.id)
    session.append_transcript({ "role" => "user", "content" => "hi" })

    described_class.perform_now(stale.id, note)

    expect(session.reload.transcript.map { |e| e["content"] }).to eq([ "hi", note ])
  end

  it "does not write and requeues while a turn holds the lock" do
    Redis.current.set(lock_key, "turn-token", nx: true, ex: ChatStreamJob::LOCK_TTL)

    expect { described_class.perform_now(session.id, note) }
      .to have_enqueued_job(described_class).with(session.id, note, kind_of(Integer))

    expect(session.reload.transcript).to be_blank
    expect(Redis.current.get(lock_key)).to eq("turn-token")
  end

  it "gives up once the deadline passes" do
    Redis.current.set(lock_key, "turn-token", nx: true, ex: ChatStreamJob::LOCK_TTL)

    expect { described_class.perform_now(session.id, note, 1.minute.ago.to_i) }
      .not_to have_enqueued_job(described_class)
    expect(session.reload.transcript).to be_blank
  end
end
