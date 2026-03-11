# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::DeliveryQueue do
  let(:channel) { create(:channel, :slack) }
  let(:agent) { create(:agent) }

  describe ".enqueue" do
    it "creates a pending delivery queue entry" do
      result = described_class.enqueue(
        channel: channel,
        recipient: "+15551234567",
        content: "Hello!"
      )

      expect(result.success?).to be true
      entry = result.data[:entry]
      expect(entry).to be_a(DeliveryQueueEntry)
      expect(entry.status).to eq("pending")
      expect(entry.recipient).to eq("+15551234567")
      expect(entry.content).to eq("Hello!")
    end

    it "accepts optional agent and session" do
      result = described_class.enqueue(
        channel: channel,
        recipient: "user@example.com",
        content: "Test",
        agent: agent
      )

      expect(result.success?).to be true
      expect(result.data[:entry].agent).to eq(agent)
    end
  end

  describe ".deliver" do
    let(:entry) { create(:delivery_queue_entry, channel: channel) }

    it "marks entry as sent on success" do
      adapter = instance_double("Channels::SlackAdapter")
      allow(Channels::Registry).to receive(:adapter_for).with(channel).and_return(adapter)
      allow(adapter).to receive(:send_message).and_return(ServiceResponse.success(data: {}))

      result = described_class.deliver(entry)

      expect(result.success?).to be true
      entry.reload
      expect(entry.status).to eq("sent")
      expect(entry.sent_at).not_to be_nil
    end

    it "retries on failure with exponential backoff" do
      adapter = instance_double("Channels::SlackAdapter")
      allow(Channels::Registry).to receive(:adapter_for).with(channel).and_return(adapter)
      allow(adapter).to receive(:send_message).and_return(ServiceResponse.failure(error: "timeout"))

      result = described_class.deliver(entry)

      expect(result.success?).to be false
      entry.reload
      expect(entry.status).to eq("pending")
      expect(entry.attempts).to eq(1)
      expect(entry.last_error).to eq("timeout")
      expect(entry.next_attempt_at).to be > Time.current
    end

    it "moves to dead_letter after max attempts" do
      entry.update!(attempts: 4, max_attempts: 5)
      adapter = instance_double("Channels::SlackAdapter")
      allow(Channels::Registry).to receive(:adapter_for).with(channel).and_return(adapter)
      allow(adapter).to receive(:send_message).and_return(ServiceResponse.failure(error: "permanent failure"))

      described_class.deliver(entry)

      entry.reload
      expect(entry.status).to eq("dead_letter")
      expect(entry.attempts).to eq(5)
    end
  end

  describe ".process_pending" do
    it "processes due entries" do
      create(:delivery_queue_entry, channel: channel, next_attempt_at: 1.minute.ago)

      adapter = instance_double("Channels::SlackAdapter")
      allow(Channels::Registry).to receive(:adapter_for).and_return(adapter)
      allow(adapter).to receive(:send_message).and_return(ServiceResponse.success(data: {}))

      result = described_class.process_pending

      expect(result.success?).to be true
      expect(result.data[:sent]).to eq(1)
    end
  end
end
