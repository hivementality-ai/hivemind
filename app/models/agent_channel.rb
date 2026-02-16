# frozen_string_literal: true

class AgentChannel < ApplicationRecord
  belongs_to :agent
  belongs_to :channel
  
  validates :agent_id, presence: true
  validates :channel_id, presence: true
  validates :agent_id, uniqueness: { scope: :channel_id }
  validates :vault_token_key, presence: true, if: :has_bot_token?
  
  scope :default_for_channel, ->(channel) { where(channel: channel, is_default: true) }
  scope :with_bot_token, -> { where.not(vault_token_key: [nil, ""]) }
  
  before_validation :set_vault_token_key, if: -> { vault_token_key.blank? }
  after_save :ensure_single_default_per_channel, if: -> { saved_change_to_is_default? && is_default? }
  
  def bot_token
    return nil unless vault_token_key.present?
    
    entry = VaultEntry.find_by(namespace: "channel_credentials", key: vault_token_key)
    entry&.value
  end
  
  def bot_token=(value)
    return if value.blank?
    
    self.vault_token_key = "slack_agent_#{agent_id}_bot_token" if vault_token_key.blank?
    
    VaultEntry.find_or_create_by(namespace: "channel_credentials", key: vault_token_key) do |entry|
      entry.value = value
    end.tap do |entry|
      entry.update!(value: value) if entry.persisted?
    end
    
    # Auto-detect bot_user_id from Slack API
    fetch_bot_user_id
  end
  
  def has_bot_token?
    vault_token_key.present? && bot_token.present?
  end
  
  private
  
  def set_vault_token_key
    self.vault_token_key = "slack_agent_#{agent_id}_bot_token"
  end
  
  def ensure_single_default_per_channel
    # Ensure only one default per channel
    AgentChannel.where(channel: channel, is_default: true)
               .where.not(id: id)
               .update_all(is_default: false)
  end
  
  def fetch_bot_user_id
    return unless has_bot_token?
    
    begin
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
      Rails.logger.error("Failed to fetch bot_user_id for AgentChannel #{id}: #{e.message}")
    end
  end
end