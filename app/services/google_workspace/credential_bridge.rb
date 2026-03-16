# frozen_string_literal: true

module GoogleWorkspace
  class CredentialBridge
    CREDS_DIR = "/tmp/gws-creds"
    VAULT_NAMESPACE = "google_workspace"

    def self.call(&block)
      new.call(&block)
    end

    def call
      ensure_tokens_valid!

      cred_file = write_temp_credentials
      env = { "GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE" => cred_file }

      yield(env)
    ensure
      FileUtils.rm_f(cred_file) if cred_file
    end

    def self.configured?
      VaultEntry.exists?(namespace: VAULT_NAMESPACE, key: "access_token") &&
        VaultEntry.exists?(namespace: VAULT_NAMESPACE, key: "refresh_token")
    end

    def self.connected_email
      VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "email")&.value
    end

    def self.granted_scopes
      VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "scopes")&.value
    end

    def self.store_tokens(access_token:, refresh_token:, expires_in: nil, expires_at: nil, scope: nil, email: nil, client_id: nil, client_secret: nil)
      if expires_at.present?
        computed_expires_at = expires_at.is_a?(String) ? expires_at : expires_at.iso8601
      elsif expires_in.present?
        computed_expires_at = (Time.current + expires_in.to_i.seconds).iso8601
      end

      store(VAULT_NAMESPACE, "access_token", access_token)
      store(VAULT_NAMESPACE, "refresh_token", refresh_token) if refresh_token.present?
      store(VAULT_NAMESPACE, "expires_at", computed_expires_at) if computed_expires_at.present?
      store(VAULT_NAMESPACE, "scopes", scope) if scope.present?
      store(VAULT_NAMESPACE, "email", email) if email.present?
      store(VAULT_NAMESPACE, "client_id", client_id) if client_id.present?
      store(VAULT_NAMESPACE, "client_secret", client_secret) if client_secret.present?
    end

    # Import credentials JSON from `gws auth export` or full token output.
    # Handles two formats:
    #   1. Full: { access_token, refresh_token, client_id, client_secret, expiry }
    #   2. Minimal (gws auth export): { client_id, client_secret, refresh_token, type }
    def self.import_credentials(json_string)
      data = JSON.parse(json_string)

      refresh_token = data["refresh_token"]
      client_id = data["client_id"]
      client_secret = data["client_secret"]

      raise "Missing refresh_token in credentials" unless refresh_token.present?

      # Store client credentials first so OAuthClient can use them for refresh
      store(VAULT_NAMESPACE, "client_id", client_id) if client_id.present?
      store(VAULT_NAMESPACE, "client_secret", client_secret) if client_secret.present?
      store(VAULT_NAMESPACE, "refresh_token", refresh_token)

      access_token = data["access_token"] || data["token"]

      # If no access_token provided, use refresh_token to get one
      if access_token.blank? && client_id.present? && client_secret.present?
        client = GoogleWorkspace::OAuthClient.new
        result = client.refresh_token(refresh_token)
        raise "Failed to refresh token: #{result.error}" unless result.success?

        access_token = result.data[:access_token]
        expires_in = result.data[:expires_in]

        store(VAULT_NAMESPACE, "access_token", access_token)
        store(VAULT_NAMESPACE, "expires_at", (Time.current + expires_in.to_i.seconds).iso8601) if expires_in
      else
        store(VAULT_NAMESPACE, "access_token", access_token) if access_token.present?
        if data["expiry"].present? || data["expires_at"].present?
          store(VAULT_NAMESPACE, "expires_at", data["expiry"] || data["expires_at"])
        end
      end

      # Fetch email for display
      if access_token.present?
        begin
          client = GoogleWorkspace::OAuthClient.new
          user_result = client.fetch_user_info(access_token)
          store(VAULT_NAMESPACE, "email", user_result.data[:email]) if user_result.success? && user_result.data[:email]
        rescue StandardError
          # Not critical
        end
      end
    end

    def self.disconnect!
      %w[access_token refresh_token expires_at scopes email client_id client_secret].each do |key|
        VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: key)&.destroy
      end
    end

    private

    def ensure_tokens_valid!
      expires_at_str = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "expires_at")&.value
      return unless expires_at_str.present?

      expires_at = Time.parse(expires_at_str)
      return unless Time.current > expires_at - 5.minutes

      refresh_token = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "refresh_token")&.value
      raise "No refresh token available" unless refresh_token.present?

      client = GoogleWorkspace::OAuthClient.new
      result = client.refresh_token(refresh_token)
      raise result.error unless result.success?

      new_expires_at = Time.current + result.data[:expires_in].to_i.seconds
      self.class.send(:store, VAULT_NAMESPACE, "access_token", result.data[:access_token])
      self.class.send(:store, VAULT_NAMESPACE, "expires_at", new_expires_at.iso8601)
    end

    def write_temp_credentials
      FileUtils.mkdir_p(CREDS_DIR, mode: 0o700) unless Dir.exist?(CREDS_DIR)

      creds = {}
      %w[access_token refresh_token expires_at client_id client_secret].each do |key|
        val = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: key)&.value
        creds[key] = val if val.present?
      end

      creds["type"] = "authorized_user"
      creds["token_type"] = "Bearer"
      creds["expiry"] = creds.delete("expires_at") if creds["expires_at"]

      path = File.join(CREDS_DIR, SecureRandom.hex(16))
      File.write(path, creds.to_json, perm: 0o600)
      path
    end

    def self.store(namespace, key, value)
      entry = VaultEntry.find_or_initialize_by(namespace: namespace, key: key)
      entry.value = value
      entry.save!
    end
  end
end
