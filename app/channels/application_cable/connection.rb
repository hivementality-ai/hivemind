# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      if (verified_user = env["warden"]&.user)
        verified_user
      elsif (token_user = user_from_bearer_token)
        token_user
      else
        reject_unauthorized_connection
      end
    end

    # Headless clients (the desktop app's Tauri WebSocket plugin) authenticate
    # with the same bearer ApiToken used for REST calls, sent as a custom
    # `Authorization: Bearer hv_...` handshake header. Browsers can't set
    # custom WebSocket headers, so the warden/Devise-cookie path above remains
    # the path for the web UI. The token is only ever read from the request
    # header — never from URL params — and is never logged.
    def user_from_bearer_token
      header = request.headers["Authorization"]
      return nil if header.blank?

      token = header.to_s.sub(/\ABearer /, "")
      return nil if token.blank?

      api_token = ApiToken.authenticate(token)
      return nil unless api_token

      api_token.touch_last_used!
      api_token.user
    end
  end
end
