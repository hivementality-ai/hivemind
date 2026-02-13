# frozen_string_literal: true

class ApprovalRequest < ApplicationRecord
  belongs_to :agent

  STATUSES = %w[pending approved rejected expired].freeze

  validates :action, presence: true
  validates :resource, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :requested_at, presence: true

  before_validation :set_requested_at, on: :create
  before_validation :set_default_expiry, on: :create

  scope :pending, -> { where(status: "pending") }
  scope :resolved, -> { where(status: %w[approved rejected]) }
  scope :expired, -> { where(status: "expired") }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def expired?
    status == "expired" || (expires_at.present? && expires_at < Time.current)
  end

  def expire!
    update(status: "expired", resolved_at: Time.current)
  end

  private

  def set_requested_at
    self.requested_at ||= Time.current
  end

  def set_default_expiry
    self.expires_at ||= 24.hours.from_now
  end
end
