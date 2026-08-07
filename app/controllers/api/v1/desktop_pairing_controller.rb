# frozen_string_literal: true

module Api
  module V1
    class DesktopPairingController < ApiController
      # ApiController already skips Devise's :authenticate_user! for the
      # whole api/v1 namespace, so the callback is no longer in this class's
      # chain — skipping it again here raises at eager load. Bearer auth via
      # authenticate_api_token is what authorizes revoke_self.

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
