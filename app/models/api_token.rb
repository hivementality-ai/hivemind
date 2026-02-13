# frozen_string_literal: true

class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  before_validation :generate_token, on: :create

  attr_accessor :raw_token

  def self.authenticate(token)
    return nil if token.blank?

    digest = Digest::SHA256.hexdigest(token)
    active.find_by(token_digest: digest)
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  private

  def generate_token
    raw = SecureRandom.urlsafe_base64(32)
    self.raw_token = "hv_#{raw}"
    self.token_digest = Digest::SHA256.hexdigest(self.raw_token)
  end
end
