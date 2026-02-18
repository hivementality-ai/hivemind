# frozen_string_literal: true

module Vault
  # Two-stage vault write confirmation.
  # Agent requests a write → system explains what it does → user approves → write persists.
  class WriteConfirmation
    CONFIRMATION_TTL = 15 * 60 # 15 minutes
    REDIS_NAMESPACE = "vault_write_confirmation"

    def self.request_write(agent:, namespace:, key:, value:, purpose: nil, tool_binding: nil)
      new.request_write(
        agent: agent,
        namespace: namespace,
        key: key,
        value: value,
        purpose: purpose,
        tool_binding: tool_binding
      )
    end

    def self.confirm_write(confirmation_id:, agent:)
      new.confirm_write(confirmation_id: confirmation_id, agent: agent)
    end

    def request_write(agent:, namespace:, key:, value:, purpose: nil, tool_binding: nil)
      confirmation_id = SecureRandom.hex(32)

      # Detect what kind of credential this looks like
      identified = Vault::Redactor.identify(value)
      redacted = Vault::Redactor.redact(value)

      # Figure out what tools this enables
      enabled_tools = find_tools_needing(namespace, key)

      # Store pending write in Redis
      store_pending(confirmation_id, {
        agent_id: agent.id,
        agent_name: agent.name,
        namespace: namespace,
        key: key,
        value: value,
        purpose: purpose,
        tool_binding: tool_binding
      })

      {
        status: "pending_confirmation",
        confirmation_id: confirmation_id,
        explanation: {
          key: "#{namespace}.#{key}",
          redacted_value: redacted,
          identified_as: identified,
          purpose: purpose || "Store credential for #{namespace}",
          enables_tools: enabled_tools.map(&:name),
          scope: "Global — available to all agents with these tools assigned",
          requested_by: agent.name
        },
        expires_in_minutes: CONFIRMATION_TTL / 60
      }
    end

    def confirm_write(confirmation_id:, agent:)
      pending = retrieve_pending(confirmation_id)
      return { status: "error", message: "Confirmation expired or invalid" } unless pending

      # Create or update the vault entry (global — no agent_id scoping)
      entry = VaultEntry.find_or_initialize_by(
        namespace: pending["namespace"],
        key: pending["key"],
        agent_id: nil # Global
      )

      entry.update!(
        encrypted_value: pending["value"],
        tool_binding: pending["tool_binding"],
        metadata: (entry.metadata || {}).merge(
          "purpose" => pending["purpose"],
          "written_by_agent" => pending["agent_name"],
          "written_at" => Time.current.iso8601
        )
      )

      # Clean up Redis
      delete_pending(confirmation_id)

      # Audit log
      AuditLog.create(
        actor_type: "Agent",
        actor_id: pending["agent_id"].to_s,
        action: "vault_write",
        resource: "VaultEntry##{entry.id}",
        metadata: {
          namespace: pending["namespace"],
          key: pending["key"],
          tool_binding: pending["tool_binding"],
          redacted_value: Vault::Redactor.redact(pending["value"])
        }
      )

      {
        status: "written",
        key: "#{pending['namespace']}.#{pending['key']}",
        message: "Credential stored ✅",
        redacted_value: Vault::Redactor.redact(pending["value"])
      }
    rescue StandardError => e
      { status: "error", message: "Failed to store credential: #{e.message}" }
    end

    private

    def find_tools_needing(namespace, key)
      Tool.enabled.where("required_credentials @> ?", [{ namespace: namespace, key: key }].to_json)
    rescue StandardError
      # If required_credentials column doesn't exist yet or query fails
      []
    end

    def store_pending(confirmation_id, data)
      redis = Redis.current
      redis_key = "#{REDIS_NAMESPACE}:#{confirmation_id}"
      redis.setex(redis_key, CONFIRMATION_TTL, JSON.generate(data))
    rescue StandardError => e
      Rails.logger.warn("Vault WriteConfirmation: failed to store pending: #{e.message}")
    end

    def retrieve_pending(confirmation_id)
      redis = Redis.current
      redis_key = "#{REDIS_NAMESPACE}:#{confirmation_id}"
      data = redis.get(redis_key)
      data ? JSON.parse(data) : nil
    rescue StandardError => e
      Rails.logger.warn("Vault WriteConfirmation: failed to retrieve pending: #{e.message}")
      nil
    end

    def delete_pending(confirmation_id)
      redis = Redis.current
      redis_key = "#{REDIS_NAMESPACE}:#{confirmation_id}"
      redis.del(redis_key)
    rescue StandardError => e
      Rails.logger.warn("Vault WriteConfirmation: failed to delete pending: #{e.message}")
    end
  end
end
