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

    def self.store_tokens(access_token:, refresh_token:, expires_in:, scope:, email: nil)
      expires_at = Time.current + expires_in.to_i.seconds

      store(VAULT_NAMESPACE, "access_token", access_token)
      store(VAULT_NAMESPACE, "refresh_token", refresh_token) if refresh_token.present?
      store(VAULT_NAMESPACE, "expires_at", expires_at.iso8601)
      store(VAULT_NAMESPACE, "scopes", scope)
      store(VAULT_NAMESPACE, "email", email) if email.present?
    end

    def self.disconnect!
      %w[access_token refresh_token expires_at scopes email].each do |key|
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

      access_token = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "access_token")&.value
      refresh_token = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "refresh_token")&.value
      expires_at = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "expires_at")&.value

      path = File.join(CREDS_DIR, SecureRandom.hex(16))
      creds = {
        access_token: access_token,
        refresh_token: refresh_token,
        token_type: "Bearer",
        expiry: expires_at
      }.to_json

      File.write(path, creds, perm: 0o600)
      path
    end

    def self.store(namespace, key, value)
      entry = VaultEntry.find_or_initialize_by(namespace: namespace, key: key)
      entry.value = value
      entry.save!
    end
  end
end
