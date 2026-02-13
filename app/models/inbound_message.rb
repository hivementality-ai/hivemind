# frozen_string_literal: true

class InboundMessage < ApplicationRecord
  belongs_to :channel

  validates :external_id, presence: true, uniqueness: { scope: :channel_id }
  validates :sender, presence: true
  validates :received_at, presence: true

  scope :recent, -> { order(received_at: :desc) }
  scope :for_channel, ->(channel) { where(channel: channel) }
end
