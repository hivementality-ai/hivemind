# frozen_string_literal: true

module Approvals
  # Decides which tool calls leave the house and so need a person's yes first.
  # Reads never ask. Each agent can turn a category off or on again; unset means ask.
  class AskFirst
    # Category key => the switch label shown on the agent's page, in plain words.
    CATEGORIES = {
      "send_email" => "Ask me before sending email",
      "post_message" => "Ask me before posting a message to a channel",
      "delete_file" => "Ask me before deleting a file",
      "external_write" => "Ask me before changing something on another website or service"
    }.freeze

    SAFE_HTTP_METHODS = %w[GET HEAD OPTIONS].freeze
    GMAIL_SENDING_ACTIONS = %w[send reply].freeze
    EMAIL_SENDING_ACTIONS = %w[send send_html].freeze
    DELETE_ACTIONS = %w[delete rm].freeze

    class << self
      # @param executor_type [String] the tool's executor type
      # @param input [Hash] arguments the model passed
      # @return [String, nil] a CATEGORIES key, or nil when the call is not one that leaves the house
      def category(executor_type:, input:)
        input = input.is_a?(Hash) ? input.stringify_keys : {}
        action = input["action"].to_s.strip

        case executor_type.to_s
        when "google_gmail", "gmail" then "send_email" if GMAIL_SENDING_ACTIONS.include?(action)
        when "email" then "send_email" if EMAIL_SENDING_ACTIONS.include?(action)
        when "message" then "post_message" if action.blank? || action == "send"
        when "cloud_storage", "drive" then "delete_file" if DELETE_ACTIONS.include?(action)
        when "http_request" then "external_write" if http_write?(input, action)
        end
      end

      # @param agent [Agent, nil]
      # @param executor_type [String]
      # @param input [Hash]
      # @return [String, nil] the category to ask about, or nil when the call can just run
      def category_to_ask(agent:, executor_type:, input:)
        found = category(executor_type:, input:)
        return unless found
        return found unless agent

        found if agent.asks_first?(found)
      end

      private

      def http_write?(input, action)
        return false unless action.blank? || action == "request"

        !SAFE_HTTP_METHODS.include?((input["method"].presence || "GET").to_s.upcase)
      end
    end
  end
end
