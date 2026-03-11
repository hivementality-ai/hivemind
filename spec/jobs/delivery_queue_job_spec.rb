# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliveryQueueJob do
  describe "#perform" do
    it "calls DeliveryQueue.process_pending" do
      allow(Channels::DeliveryQueue).to receive(:process_pending)
        .and_return(ServiceResponse.success(data: { sent: 0, failed: 0 }))

      expect { described_class.new.perform }.not_to raise_error
      expect(Channels::DeliveryQueue).to have_received(:process_pending)
    end

    it "handles errors gracefully" do
      allow(Channels::DeliveryQueue).to receive(:process_pending)
        .and_return(ServiceResponse.failure(error: "Redis down"))

      expect { described_class.new.perform }.not_to raise_error
    end
  end
end
