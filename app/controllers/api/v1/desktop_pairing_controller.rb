# frozen_string_literal: true

module Api
  module V1
    class DesktopPairingController < ApiController
      # Called by the desktop app itself (no browser/Devise session — it
      # only holds the bearer ApiToken), so only Devise's cookie-session
      # gate is skipped here. ApiController's authenticate_api_token still
      # runs and is what authorizes this request.
      skip_before_action :authenticate_user!, only: [ :revoke_self ]

      # DELETE /api/v1/desktop_pairing/token
      #
      # Revokes the ApiToken that authenticated this very request — used by
      # the desktop app's "Sign out" to invalidate its own credential
      # server-side before clearing the local OS keychain entry.
      def revoke_self
        current_api_token.revoke!
        head :no_content
      end
    end
  end
end
