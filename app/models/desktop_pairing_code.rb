# frozen_string_literal: true

class DesktopPairingCode < ApplicationRecord
  belongs_to :user

  TTL = 5.minutes

  validates :device_name, presence: true
  validates :code_challenge, presence: true

  before_validation :generate_code, on: :create
  before_validation :set_expiration, on: :create

  scope :usable, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  # Verifies the PKCE code_verifier against the stored code_challenge and,
  # on success, atomically marks the code as used so it cannot be replayed.
  # Returns the consumed DesktopPairingCode, or nil if the code is invalid,
  # expired, already used, or the verifier doesn't match.
  def self.exchange!(code:, code_verifier:)
    return nil if code.blank? || code_verifier.blank?

    pairing_code = usable.find_by(code: code)
    return nil unless pairing_code
    return nil unless pairing_code.matches_verifier?(code_verifier)

    # Guard against replay: only succeeds if still unused at update time.
    updated = pairing_code.class.usable.where(id: pairing_code.id).update_all(used_at: Time.current)
    return nil if updated.zero?

    pairing_code.reload
    pairing_code
  end

  def matches_verifier?(code_verifier)
    ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(code_verifier), code_challenge)
  end

  def expired?
    expires_at < Time.current
  end

  def used?
    used_at.present?
  end

  private

  def generate_code
    self.code ||= SecureRandom.urlsafe_base64(32)
  end

  def set_expiration
    self.expires_at ||= TTL.from_now
  end
end
