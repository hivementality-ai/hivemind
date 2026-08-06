# frozen_string_literal: true

require "rails_helper"

RSpec.describe DesktopPairingCode, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
  end

  describe "validations" do
    it { should validate_presence_of(:device_name) }
    it { should validate_presence_of(:code_challenge) }
  end

  describe "generation" do
    it "generates a unique code and a default expiration on create" do
      pairing_code = create(:desktop_pairing_code)

      expect(pairing_code.code).to be_present
      expect(pairing_code.expires_at).to be_within(1.second).of(DesktopPairingCode::TTL.from_now)
    end
  end

  describe ".exchange!" do
    let(:code_verifier) { "correct-verifier" }
    let(:code_challenge) { Digest::SHA256.hexdigest(code_verifier) }
    let!(:pairing_code) { create(:desktop_pairing_code, code_challenge: code_challenge) }

    it "returns the pairing code and marks it used with a correct verifier" do
      result = DesktopPairingCode.exchange!(code: pairing_code.code, code_verifier: code_verifier)

      expect(result).to eq(pairing_code)
      expect(pairing_code.reload.used?).to be true
    end

    it "returns nil with an incorrect verifier and leaves the code usable" do
      result = DesktopPairingCode.exchange!(code: pairing_code.code, code_verifier: "wrong")

      expect(result).to be_nil
      expect(pairing_code.reload.used?).to be false
    end

    it "returns nil for an expired code" do
      expired = create(:desktop_pairing_code, :expired, code_challenge: code_challenge)
      expect(DesktopPairingCode.exchange!(code: expired.code, code_verifier: code_verifier)).to be_nil
    end

    it "returns nil for an already-used code" do
      used = create(:desktop_pairing_code, :used, code_challenge: code_challenge)
      expect(DesktopPairingCode.exchange!(code: used.code, code_verifier: code_verifier)).to be_nil
    end

    it "returns nil for an unknown code" do
      expect(DesktopPairingCode.exchange!(code: "unknown", code_verifier: code_verifier)).to be_nil
    end

    it "is single-use even if called twice with a valid verifier" do
      expect(DesktopPairingCode.exchange!(code: pairing_code.code, code_verifier: code_verifier)).to eq(pairing_code)
      expect(DesktopPairingCode.exchange!(code: pairing_code.code, code_verifier: code_verifier)).to be_nil
    end
  end

  describe "#matches_verifier?" do
    it "returns true when SHA-256(verifier) equals code_challenge" do
      verifier = "some-verifier"
      pairing_code = build(:desktop_pairing_code, code_challenge: Digest::SHA256.hexdigest(verifier))

      expect(pairing_code.matches_verifier?(verifier)).to be true
      expect(pairing_code.matches_verifier?("other")).to be false
    end
  end
end
