# frozen_string_literal: true

class Channel < ApplicationRecord
  validates :channel_type, presence: true
  validates :name, presence: true

  has_many :agent_channels, dependent: :destroy
  has_many :agents, through: :agent_channels
  has_many :channel_threads, dependent: :destroy

  scope :enabled_channels, -> { where(enabled: true) }

  after_initialize :set_defaults

  private

  def set_defaults
    self.config ||= {}
    self.enabled = true if enabled.nil?
  end
end
