# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionSignal do
  let(:session_id) { 42 }

  after { described_class.clear(session_id) }

  describe ".set / .check" do
    it "stores and retrieves a cancel signal" do
      described_class.cancel(session_id)
      signal = described_class.check(session_id)

      expect(signal[:type]).to eq("cancel")
      expect(signal[:message]).to be_nil
    end

    it "stores and retrieves a redirect signal with message" do
      described_class.redirect(session_id, message: "do this instead")
      signal = described_class.check(session_id)

      expect(signal[:type]).to eq("redirect")
      expect(signal[:message]).to eq("do this instead")
    end

    it "stores and retrieves an inject signal with message" do
      described_class.inject(session_id, message: "also include Q4 numbers")
      signal = described_class.check(session_id)

      expect(signal[:type]).to eq("inject")
      expect(signal[:message]).to eq("also include Q4 numbers")
    end

    it "consumes signal on check (read-once)" do
      described_class.cancel(session_id)
      described_class.check(session_id)

      expect(described_class.check(session_id)).to be_nil
    end

    it "returns nil when no signal exists" do
      expect(described_class.check(session_id)).to be_nil
    end
  end

  describe ".peek" do
    it "reads without consuming" do
      described_class.cancel(session_id)

      expect(described_class.peek(session_id)).to be_present
      expect(described_class.peek(session_id)).to be_present
    end
  end

  describe ".clear" do
    it "removes a pending signal" do
      described_class.cancel(session_id)
      described_class.clear(session_id)

      expect(described_class.check(session_id)).to be_nil
    end
  end

  describe "validations" do
    it "rejects unknown signal types" do
      expect { described_class.set(session_id, type: "explode") }.to raise_error(ArgumentError, /Unknown signal type/)
    end

    it "requires message for redirect" do
      expect { described_class.redirect(session_id, message: "") }.to raise_error(ArgumentError, /Message required/)
    end

    it "requires message for inject" do
      expect { described_class.inject(session_id, message: nil) }.to raise_error(ArgumentError, /Message required/)
    end

    it "does not require message for cancel" do
      expect { described_class.cancel(session_id) }.not_to raise_error
    end
  end

  describe "last-write-wins" do
    it "overwrites previous signal" do
      described_class.cancel(session_id)
      described_class.redirect(session_id, message: "new plan")

      signal = described_class.check(session_id)
      expect(signal[:type]).to eq("redirect")
    end
  end
end
