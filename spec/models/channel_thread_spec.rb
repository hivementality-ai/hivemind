# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelThread, type: :model do
  let(:agent) { create(:agent) }
  let(:channel) { create(:channel) }

  describe "validations" do
    subject { build(:channel_thread, agent: agent, channel: channel, external_thread_id: "thread123") }

    it { is_expected.to validate_presence_of(:external_thread_id) }
    it { is_expected.to validate_uniqueness_of(:external_thread_id).scoped_to(:channel_id) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:agent) }
    it { is_expected.to belong_to(:channel) }
  end

  describe "scopes" do
    let!(:old_thread) { create(:channel_thread, last_active_at: 2.hours.ago) }
    let!(:new_thread) { create(:channel_thread, last_active_at: 1.hour.ago) }

    describe ".recent_first" do
      it "orders by last_active_at descending" do
        result = described_class.recent_first
        expect(result.to_a).to eq([ new_thread, old_thread ])
      end
    end

    describe ".for_thread" do
      let!(:matching_thread) { create(:channel_thread, channel: channel, external_thread_id: "thread123") }
      let!(:other_thread) { create(:channel_thread, external_thread_id: "thread456") }

      it "returns only threads matching channel and external_thread_id" do
        result = described_class.for_thread(channel, "thread123")
        expect(result).to contain_exactly(matching_thread)
      end
    end
  end

  describe "#touch_activity!" do
    let(:channel_thread) { create(:channel_thread, last_active_at: 1.hour.ago) }

    it "updates last_active_at to current time" do
      expect { channel_thread.touch_activity! }
        .to change { channel_thread.reload.last_active_at }
        .to be_within(1.second).of(Time.current)
    end
  end

  describe ".claim_thread" do
    context "when thread doesn't exist" do
      it "creates a new channel thread" do
        expect {
          described_class.claim_thread(
            channel: channel,
            agent: agent,
            thread_id: "new_thread"
          )
        }.to change(described_class, :count).by(1)

        thread = described_class.last
        expect(thread.channel).to eq(channel)
        expect(thread.agent).to eq(agent)
        expect(thread.external_thread_id).to eq("new_thread")
        expect(thread.last_active_at).to be_within(1.second).of(Time.current)
      end
    end

    context "when thread already exists" do
      let!(:existing_thread) {
        create(:channel_thread,
               channel: channel,
               external_thread_id: "existing_thread",
               last_active_at: 2.hours.ago)
      }

      it "returns the existing thread without creating a new one" do
        expect {
          result = described_class.claim_thread(
            channel: channel,
            agent: agent,
            thread_id: "existing_thread"
          )
          expect(result).to eq(existing_thread)
        }.not_to change(described_class, :count)
      end
    end
  end

  describe ".thread_owner" do
    let!(:thread_owner) { create(:agent) }
    let!(:channel_thread) {
      create(:channel_thread,
             channel: channel,
             agent: thread_owner,
             external_thread_id: "owned_thread")
    }

    context "when thread exists" do
      it "returns the owning agent" do
        owner = described_class.thread_owner(channel: channel, thread_id: "owned_thread")
        expect(owner).to eq(thread_owner)
      end
    end

    context "when thread doesn't exist" do
      it "returns nil" do
        owner = described_class.thread_owner(channel: channel, thread_id: "nonexistent")
        expect(owner).to be_nil
      end
    end

    context "when thread_id is nil" do
      it "returns nil" do
        owner = described_class.thread_owner(channel: channel, thread_id: nil)
        expect(owner).to be_nil
      end
    end
  end

  describe "callbacks" do
    describe "setting last_active_at" do
      let(:channel_thread) { build(:channel_thread, last_active_at: nil) }

      it "sets last_active_at before validation" do
        channel_thread.save!
        expect(channel_thread.last_active_at).to be_within(1.second).of(Time.current)
      end
    end
  end
end
