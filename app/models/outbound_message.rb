# frozen_string_literal: true

class OutboundMessage < ApplicationRecord
  belongs_to :channel

  validates :recipient, presence: true
  validates :sent_at, presence: true

  scope :recent, -> { order(sent_at: :desc) }
  scope :for_channel, ->(channel) { where(channel: channel) }
end
