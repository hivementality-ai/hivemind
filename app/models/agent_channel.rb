# frozen_string_literal: true

class AgentChannel < ApplicationRecord
  belongs_to :agent
  belongs_to :channel

  validates :agent_id, presence: true
  validates :channel_id, presence: true
  validates :agent_id, uniqueness: { scope: :channel_id }
  validates :vault_token_key, presence: true, if: :has_bot_token?

  scope :default_for_channel, ->(channel) { where(channel: channel, is_default: true) }
  scope :with_bot_token, -> { where.not(vault_token_key: [ nil, "" ]) }

  before_validation :set_vault_token_key, if: -> { vault_token_key.blank? }
  after_save :ensure_single_default_per_channel, if: -> { saved_change_to_is_default? && is_default? }

  delegate :channel_type, to: :channel, allow_nil: true

  def bot_token
    return nil unless vault_token_key.present?

    entry = VaultEntry.find_by(namespace: "channel_credentials", key: vault_token_key)
    entry&.value
  end

  def bot_token=(value)
    return if value.blank?

    self.vault_token_key = generate_vault_token_key if vault_token_key.blank?

    VaultEntry.find_or_create_by(namespace: "channel_credentials", key: vault_token_key) do |entry|
      entry.value = value
    end.tap do |entry|
      entry.update!(value: value) if entry.persisted?
    end

    # Auto-detect bot_user_id from platform API
    fetch_bot_user_id
  end

  def has_bot_token?
    vault_token_key.present? && bot_token.present?
  end

  def discord?
    channel_type == "discord"
  end

  def slack?
    channel_type == "slack"
  end

  private

  def platform_prefix
    channel_type.presence || "slack"
  end

  def generate_vault_token_key
    "#{platform_prefix}_agent_#{agent_id}_bot_token"
  end

  def set_vault_token_key
    self.vault_token_key = generate_vault_token_key
  end

  def ensure_single_default_per_channel
    AgentChannel.where(channel: channel, is_default: true)
               .where.not(id: id)
               .update_all(is_default: false)
  end

  def fetch_bot_user_id
    return unless has_bot_token?

    if discord?
      fetch_discord_bot_user_id
    else
      fetch_slack_bot_user_id
    end
  end

  def fetch_discord_bot_user_id
    response = Faraday.get(
      "https://discord.com/api/v10/users/@me",
      nil,
      { "Authorization" => "Bot #{bot_token}" }
    )

    if response.success?
      data = JSON.parse(response.body)
      update_column(:external_bot_user_id, data["id"]) if data["id"]
    end
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Discord bot_user_id for AgentChannel #{id}: #{e.message}")
  end

  def fetch_slack_bot_user_id
    uri = URI("https://slack.com/api/auth.test")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{bot_token}"
    req["Content-Type"] = "application/json"
    req.body = {}.to_json

    response = JSON.parse(http.request(req).body)

    if response["ok"] && response["user_id"]
      update_column(:external_bot_user_id, response["user_id"])
    end
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Slack bot_user_id for AgentChannel #{id}: #{e.message}")
  end
end
