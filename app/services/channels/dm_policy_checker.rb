# frozen_string_literal: true

module Channels
  class DmPolicyChecker
    MODES = %w[open allowlist blocklist].freeze
    DEFAULT_BLOCKED_REPLY = "I'm not authorized to chat with you. Contact the admin."

    def self.call(agent_channel:, sender:, is_mention: false)
      new(agent_channel: agent_channel, sender: sender, is_mention: is_mention).call
    end

    def initialize(agent_channel:, sender:, is_mention: false)
      @agent_channel = agent_channel
      @sender = sender
      @is_mention = is_mention
      @policy = agent_channel.dm_policy.presence || {}
    end

    def call
      mode = @policy["mode"].to_s.presence || "open"

      unless MODES.include?(mode)
        return ServiceResponse.failure(error: "Unknown DM policy mode: #{mode}")
      end

      if require_mention? && !@is_mention
        return blocked_response("Message ignored: mention required in group chats")
      end

      case mode
      when "open"
        ServiceResponse.success(data: { allowed: true })
      when "allowlist"
        check_allowlist
      when "blocklist"
        check_blocklist
      end
    end

    private

    def check_allowlist
      allowed = @policy["allowed_senders"] || []

      if sender_matches?(allowed)
        ServiceResponse.success(data: { allowed: true })
      else
        blocked_response(auto_reply_message)
      end
    end

    def check_blocklist
      blocked = @policy["blocked_senders"] || []

      if sender_matches?(blocked)
        blocked_response(auto_reply_message)
      else
        ServiceResponse.success(data: { allowed: true })
      end
    end

    def sender_matches?(list)
      list.any? do |pattern|
        if pattern.include?("*")
          File.fnmatch(pattern, @sender)
        else
          pattern == @sender
        end
      end
    end

    def require_mention?
      @policy["require_mention"] == true
    end

    def auto_reply_message
      @policy["auto_reply_blocked"].presence || DEFAULT_BLOCKED_REPLY
    end

    def blocked_response(message)
      ServiceResponse.success(data: { allowed: false, reply: message })
    end
  end
end
