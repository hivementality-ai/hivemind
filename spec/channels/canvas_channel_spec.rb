# frozen_string_literal: true

require "rails_helper"

RSpec.describe CanvasChannel, type: :channel do
  let(:session) { create(:session) }

  it "subscribes to a valid session" do
    subscribe(session_id: session.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("canvas_#{session.id}")
  end

  it "rejects subscription for non-existent session" do
    subscribe(session_id: -1)
    expect(subscription).to be_rejected
  end

  it "rejects subscription without session_id" do
    subscribe(session_id: nil)
    expect(subscription).to be_rejected
  end
end
