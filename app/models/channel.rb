# frozen_string_literal: true

class Channel < ApplicationRecord
  validates :channel_type, presence: true
  validates :name, presence: true

  scope :enabled_channels, -> { where(enabled: true) }

  after_initialize :set_defaults

  private

  def set_defaults
    self.config ||= {}
    self.enabled = true if enabled.nil?
  end
end
