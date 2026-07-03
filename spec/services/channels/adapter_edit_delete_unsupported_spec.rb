# frozen_string_literal: true

require "rails_helper"

# Verifies that adapters not implementing edit/delete raise a caller-friendly error.
RSpec.describe "Unsupported adapter edit/delete" do
  let(:channel) { create(:channel, channel_type: "telegram") }

  # TelegramAdapter inherits base default — does not override edit_message/delete_message
  let(:adapter) { Channels::TelegramAdapter.new(channel) }

  describe "#edit_message" do
    it "raises NotImplementedError with a friendly message" do
      expect { adapter.edit_message("123", "new text") }
        .to raise_error(NotImplementedError, "Message editing is not supported on this channel")
    end
  end

  describe "#delete_message" do
    it "raises NotImplementedError with a friendly message" do
      expect { adapter.delete_message("123") }
        .to raise_error(NotImplementedError, "Message deletion is not supported on this channel")
    end
  end
end
