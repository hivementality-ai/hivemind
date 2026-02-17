# frozen_string_literal: true

module Api
  module V1
    class SystemController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/system/version
      def version
        if update_check_enabled?
          info = GithubReleaseChecker.update_info
          render json: info || { current: Hivemind::VERSION, error: "Unable to check for updates" }
        else
          render json: {
            current: Hivemind::VERSION,
            update_check_enabled: false
          }
        end
      end

      private

      def update_check_enabled?
        ENV.fetch("UPDATE_CHECK_ENABLED", "true") != "false"
      end
    end
  end
end
