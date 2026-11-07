# frozen_string_literal: true

# Policy for Simple mode: one app-wide setting that hides power-user features
# from menus and from the tool list offered to the model. Routes keep working
# and nothing is deleted; turning the setting off restores everything.
module SimpleMode
  SETTING_KEY = "simple_mode"

  # Sidebar entries hidden while Simple mode is on.
  HIDDEN_NAV = %i[team_chat teams hooks budgets api_tokens webhooks].freeze

  # Settings sections hidden while Simple mode is on.
  HIDDEN_SECTIONS = %i[jira trello].freeze

  # Tool executor types left out of the model's tool list while Simple mode is on.
  HIDDEN_TOOL_EXECUTORS = %w[jira trello coding_agent coding_agent_status].freeze

  # The only channel types offered: iMessage, email and one chat app (Slack).
  VISIBLE_CHANNEL_TYPES = %w[imessage email slack].freeze

  class << self
    # @return [Boolean]
    def enabled?
      Setting.get(SETTING_KEY) == "true"
    end

    # @param enabled [Boolean]
    def enabled=(enabled)
      Setting.set(SETTING_KEY, enabled ? "true" : "false")
    end

    # @param key [Symbol] a HIDDEN_NAV entry
    # @return [Boolean] whether the sidebar entry should render
    def show_nav?(key)
      !(enabled? && HIDDEN_NAV.include?(key))
    end

    # @param key [Symbol] a HIDDEN_SECTIONS entry
    # @return [Boolean] whether the settings section should render
    def show_section?(key)
      !(enabled? && HIDDEN_SECTIONS.include?(key))
    end

    # @param channel_type [String]
    # @return [Boolean]
    def show_channel_type?(channel_type)
      !enabled? || VISIBLE_CHANNEL_TYPES.include?(channel_type.to_s)
    end

    # @param tools [Array<Tool, SystemTool>] tools about to be offered to the model
    # @return [Array] the same tools minus the hidden executors when Simple mode is on
    def offered_tools(tools)
      return tools unless enabled?

      tools.reject { |tool| tool.respond_to?(:executor_type) && HIDDEN_TOOL_EXECUTORS.include?(tool.executor_type) }
    end
  end
end
