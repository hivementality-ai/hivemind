# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationChannel, type: :channel do
  let(:user) { create(:user) }

  before do
    stub_connection(current_user: user)
  end

  it "subscribes to the connected user's own notification stream" do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("notifications_user_#{user.id}")
  end

  it "does not stream any other user's notifications" do
    other_user = create(:user)

    subscribe

    expect(subscription).not_to have_stream_from("notifications_user_#{other_user.id}")
  end

  it "rejects the subscription when there is no verified user" do
    stub_connection(current_user: nil)

    subscribe

    expect(subscription).to be_rejected
  end
end
