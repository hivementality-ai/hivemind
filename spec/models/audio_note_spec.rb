# frozen_string_literal: true

require "rails_helper"

RSpec.describe AudioNote, type: :model do
  describe ".accepted_filename?" do
    it "accepts the supported audio types in any case" do
      expect(%w[a.mp3 a.M4A a.wav a.webm a.ogg].map { |name| described_class.accepted_filename?(name) }).to all(be true)
    end

    it "rejects other files" do
      expect(%w[a.pdf a.exe a].map { |name| described_class.accepted_filename?(name) }).to all(be false)
    end
  end

  describe ".max_bytes" do
    it "defaults to 200 MB" do
      expect(described_class.max_bytes).to eq(200.megabytes)
    end

    it "reads HIVEMIND_AUDIO_MAX_MB" do
      stub_const("ENV", ENV.to_h.merge("HIVEMIND_AUDIO_MAX_MB" => "5"))
      expect(described_class.max_bytes).to eq(5.megabytes)
    end
  end

  describe "#progress_text" do
    it "has plain words for every status" do
      texts = described_class::STATUSES.map { |status| build(:audio_note, status: status, error: "Nope.").progress_text }
      expect(texts.uniq.size).to eq(described_class::STATUSES.size)
      expect(texts.last).to include("Nope.")
    end
  end
end
