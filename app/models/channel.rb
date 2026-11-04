# frozen_string_literal: true

class Channel < ApplicationRecord
  # Supported messaging platforms as [label, channel_type] pairs, the single source for every view.
  PLATFORMS = [
    [ "Discord", "discord" ], [ "Slack", "slack" ], [ "Telegram", "telegram" ], [ "WhatsApp", "whatsapp" ],
    [ "Signal", "signal" ], [ "Matrix", "matrix" ], [ "Email", "email" ], [ "Mattermost", "mattermost" ],
    [ "LINE", "line" ], [ "Feishu / Lark", "feishu" ], [ "Google Chat", "google_chat" ],
    [ "Microsoft Teams", "msteams" ], [ "iMessage (BlueBubbles)", "imessage" ]
  ].freeze

  # Platform labels joined as a readable list, e.g. "Discord, Slack, and Signal".
  #
  # @param conjunction [String] word placed before the last label
  # @return [String]
  def self.platform_sentence(conjunction: "and")
    PLATFORMS.map(&:first).to_sentence(last_word_connector: ", #{conjunction} ", two_words_connector: " #{conjunction} ")
  end

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
