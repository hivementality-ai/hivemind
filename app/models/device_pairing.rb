# frozen_string_literal: true

class DevicePairing < ApplicationRecord
  enum :status, { pending: 0, approved: 1, rejected: 2, revoked: 3 }, default: :pending

  validates :device_id, presence: true, uniqueness: true
  validates :device_type, presence: true

  scope :active, -> { where(status: :approved) }

  after_initialize :set_defaults

  def approve!
    update!(status: :approved, approved_at: Time.current)
  end

  def reject!
    update!(status: :rejected)
  end

  def revoke!
    update!(status: :revoked)
  end

  private

  def set_defaults
    self.metadata ||= {}
  end
end
