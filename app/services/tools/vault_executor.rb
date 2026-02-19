# frozen_string_literal: true

module Tools
  class VaultExecutor < BaseExecutor
    # Agent-facing vault operations.
    # CRITICAL: Full values are NEVER returned to the agent. Always redacted.
    def call
      action = input["action"].to_s.strip

      case action
      when "read"
        read_entry
      when "exists"
        check_exists
      when "write"
        request_write
      when "confirm_write"
        confirm_write
      when "list_keys"
        list_keys
      when "check_tool"
        check_tool_credentials
      else
        ServiceResponse.failure(
          error: "Unknown vault action: #{action}. " \
                 "Supported: read, exists, write, confirm_write, list_keys, check_tool"
        )
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Vault error: #{e.message}")
    end

    private

    # Read a vault entry — ALWAYS returns redacted value
    def read_entry
      namespace = input["namespace"].to_s.strip
      key = input["key"].to_s.strip

      return ServiceResponse.failure(error: "namespace required") if namespace.empty?
      return ServiceResponse.failure(error: "key required") if key.empty?

      entry = VaultEntry.find_by(namespace: namespace, key: key, agent_id: nil)
      return ServiceResponse.failure(error: "Key not found: #{namespace}.#{key}") unless entry

      ServiceResponse.success(data: {
        output: "#{namespace}.#{key} = #{Vault::Redactor.redact(entry.value)}",
        exit_code: 0,
        key: "#{namespace}.#{key}",
        redacted_value: Vault::Redactor.redact(entry.value),
        tool_binding: entry.tool_binding,
        purpose: entry.metadata&.dig("purpose"),
        updated_at: entry.updated_at&.iso8601
      })
    end

    # Check if a key exists (no value returned)
    def check_exists
      namespace = input["namespace"].to_s.strip
      key = input["key"].to_s.strip

      return ServiceResponse.failure(error: "namespace required") if namespace.empty?
      return ServiceResponse.failure(error: "key required") if key.empty?

      exists = VaultEntry.exists?(namespace: namespace, key: key, agent_id: nil)

      ServiceResponse.success(data: {
        output: exists ? "#{namespace}.#{key} exists ✅" : "#{namespace}.#{key} not found ❌",
        exit_code: 0,
        exists: exists
      })
    end

    # Request a vault write (Stage 1 — returns confirmation for user approval)
    def request_write
      namespace = input["namespace"].to_s.strip
      key = input["key"].to_s.strip
      value = input["value"].to_s
      purpose = input["purpose"].to_s.strip.presence
      tool_binding = input["tool_binding"].to_s.strip.presence

      return ServiceResponse.failure(error: "namespace required") if namespace.empty?
      return ServiceResponse.failure(error: "key required") if key.empty?
      return ServiceResponse.failure(error: "value required") if value.empty?

      result = Vault::WriteConfirmation.request_write(
        agent: agent,
        namespace: namespace,
        key: key,
        value: value,
        purpose: purpose,
        tool_binding: tool_binding
      )

      ServiceResponse.success(data: result)
    end

    # Confirm a pending write (Stage 2 — persists after user approval)
    def confirm_write
      confirmation_id = input["confirmation_id"].to_s.strip
      return ServiceResponse.failure(error: "confirmation_id required") if confirmation_id.empty?

      result = Vault::WriteConfirmation.confirm_write(
        confirmation_id: confirmation_id,
        agent: agent
      )

      if result[:status] == "error"
        ServiceResponse.failure(error: result[:message])
      else
        ServiceResponse.success(data: {
          output: "#{result[:key]} stored ✅ (#{result[:redacted_value]})",
          exit_code: 0,
          **result
        })
      end
    end

    # List key names in a namespace (no values — just names and metadata)
    def list_keys
      namespace = input["namespace"].to_s.strip.presence

      entries = if namespace
                  VaultEntry.where(agent_id: nil, namespace: namespace)
      else
                  VaultEntry.where(agent_id: nil)
      end

      if entries.any?
        lines = entries.map do |e|
          purpose = e.metadata&.dig("purpose")
          binding = e.tool_binding ? " [#{e.tool_binding}]" : ""
          desc = purpose ? " — #{purpose}" : ""
          "  #{e.namespace}.#{e.key}#{binding}#{desc}"
        end

        output = "Vault keys#{namespace ? " (#{namespace})" : ""}:\n#{lines.join("\n")}"
        ServiceResponse.success(data: { output: output, exit_code: 0, count: entries.count })
      else
        ServiceResponse.success(data: {
          output: namespace ? "No keys in namespace '#{namespace}'" : "Vault is empty",
          exit_code: 0,
          count: 0
        })
      end
    end

    # Check if a tool has all required credentials
    def check_tool_credentials
      tool_name = input["tool_name"].to_s.strip
      return ServiceResponse.failure(error: "tool_name required") if tool_name.empty?

      tool = Tool.find_by(name: tool_name)
      return ServiceResponse.failure(error: "Tool '#{tool_name}' not found") unless tool

      if Tools::CredentialChecker.ready?(tool)
        ServiceResponse.success(data: {
          output: "#{tool_name}: all credentials configured ✅",
          exit_code: 0,
          ready: true
        })
      else
        summary = Tools::CredentialChecker.missing_summary(tool)
        ServiceResponse.success(data: {
          output: "#{tool_name}: #{summary}",
          exit_code: 0,
          ready: false,
          missing: Tools::CredentialChecker.missing(tool)
        })
      end
    end
  end
end
