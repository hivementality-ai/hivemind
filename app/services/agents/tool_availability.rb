# frozen_string_literal: true

module Agents
  # Checks why a tool is unavailable and returns human-readable explanations
  class ToolAvailability
    # TODO: Move to db
    TOOL_REQUIREMENTS = {
      "image_generate" => {
        provider: "openai",
        description: "image generation (DALL-E)",
        config_hint: "OpenAI API key must be configured in provider settings"
      },
      "gmail" => {
        provider: "google",
        description: "Gmail access",
        config_hint: "Google OAuth credentials must be configured"
      },
      "drive" => {
        provider: "google",
        description: "Google Drive access",
        config_hint: "Google OAuth credentials must be configured"
      },
      "jira" => {
        provider: "jira",
        description: "Jira integration",
        config_hint: "Jira API token and instance URL must be configured"
      },
      "tts" => {
        description: "text-to-speech",
        config_hint: "A TTS provider (ElevenLabs or OpenAI) must be configured"
      },
      "web_search" => {
        description: "web search",
        config_hint: "A search provider API key must be configured"
      },
      "browser" => {
        description: "browser automation",
        config_hint: "Browser container must be running"
      }
    }.freeze

    # Check why a tool is unavailable and return a human-readable explanation
    # @param tool_name [String] The tool name the agent tried to use
    # @param agent [Agent] The agent that tried to use it
    # @param available_tools [Array<Tool>] Tools currently available to the agent
    # @return [String] Human-readable explanation of why the tool is unavailable
    def self.explain(tool_name:, agent:, available_tools: [])
      new(tool_name:, agent:, available_tools:).explain
    end

    def initialize(tool_name:, agent:, available_tools: [])
      @tool_name = tool_name
      @agent = agent
      @available_tools = available_tools
    end

    def explain
      # Step 1: Does this tool exist in the system at all?
      system_tool = Tool.find_by(name: @tool_name)

      unless system_tool
        # Check if it's a known tool type that just hasn't been registered
        if known_tool_type?
          return not_registered_message
        end
        return unknown_tool_message
      end

      # Step 2: Is the tool disabled system-wide?
      unless system_tool.enabled?
        return disabled_message(system_tool)
      end

      # Step 3: Does this agent have permission?
      agent_has_tool = @agent.agent_tools.exists?(tool_id: system_tool.id)
      agent_has_any_tools = @agent.agent_tools.any?

      if agent_has_any_tools && !agent_has_tool
        return no_permission_message(system_tool)
      end

      # Step 4: Check if required credentials are missing from vault
      if system_tool.required_credentials.present?
        missing = Tools::CredentialChecker.missing(system_tool)
        if missing.any?
          return missing_credentials_message(system_tool, missing)
        end
      end

      # Step 5: Check if required provider/config is missing (legacy check)
      requirement = TOOL_REQUIREMENTS[@tool_name]
      if requirement&.dig(:provider)
        provider = ProviderConfig.find_by(adapter_type: requirement[:provider], enabled: true) rescue nil
        unless provider
          return missing_provider_message(requirement)
        end
      end

      # Fallback — tool should be available but something else is wrong
      generic_unavailable_message
    end

    # List all tools an agent CAN'T use but might want to, with reasons
    # Useful for system prompt injection so agents know their limitations upfront
    def self.limitations_summary(agent:)
      available_names = agent.agent_tools.includes(:tool).map { |at| at.tool.name }
      all_tools = Tool.enabled.pluck(:name)
      unavailable = all_tools - available_names

      return nil if unavailable.empty?

      lines = unavailable.map do |tool_name|
        req = TOOL_REQUIREMENTS[tool_name]
        desc = req ? req[:description] : tool_name.humanize.downcase
        "- #{desc} (#{tool_name})"
      end

      "Tools NOT available to you:\n#{lines.join("\n")}\n\nIf a user asks for something requiring these tools, explain clearly that you don't currently have that capability and suggest they ask an admin to enable it."
    end

    private

    def known_tool_type?
      Tool.validators_on(:executor_type).any? do |v|
        v.is_a?(ActiveModel::Validations::InclusionValidator) &&
          v.options[:in]&.include?(@tool_name)
      end
    end

    def unknown_tool_message
      "I don't have a tool called '#{@tool_name}'. This capability isn't available in the system. " \
        "If you need this functionality, ask your admin to install or configure it."
    end

    def not_registered_message
      requirement = TOOL_REQUIREMENTS[@tool_name]
      desc = requirement ? requirement[:description] : @tool_name.humanize.downcase
      hint = requirement ? " #{requirement[:config_hint]}." : ""

      "#{desc.capitalize} isn't set up yet.#{hint} " \
        "Ask your admin to register and configure the '#{@tool_name}' tool."
    end

    def disabled_message(tool)
      "#{tool.description || tool.name} is currently disabled by an administrator. " \
        "Contact your admin to re-enable it if needed."
    end

    def no_permission_message(tool)
      "I don't have permission to use #{tool.description || tool.name}. " \
        "My admin hasn't granted me access to this tool. " \
        "Ask them to add '#{tool.name}' to my tool list if you'd like me to use it."
    end

    def missing_credentials_message(tool, missing_creds)
      names = missing_creds.map { |c| c["description"] || "#{c['namespace']}.#{c['key']}" }
      tool_desc = tool.description || tool.name

      "#{tool_desc} is installed but missing required credentials: #{names.join(', ')}. " \
        "Provide these credentials or ask your admin to configure them in the vault."
    end

    def missing_provider_message(requirement)
      "I have the #{requirement[:description]} tool, but it's not fully configured. " \
        "#{requirement[:config_hint]}. Contact your admin to set this up."
    end

    def generic_unavailable_message
      "The '#{@tool_name}' tool exists but isn't available right now. " \
        "This might be a temporary issue — try again or contact your admin."
    end
  end
end
