# frozen_string_literal: true

class UpdateCheckJob < ApplicationJob
  queue_as :default

  # Runs daily via sidekiq-cron. Checks GitHub for new Hivemind releases
  # and caches the result for the admin UI banner.
  def perform
    return unless update_check_enabled?

    current = Hivemind::VERSION
    return if current == "dev"

    release = GithubReleaseChecker.latest_release
    return unless release

    if GithubReleaseChecker.send(:newer?, release[:version], current)
      Rails.cache.write("hivemind:update_available", {
        version: release[:version],
        current: current,
        breaking: release[:breaking_changes],
        changelog_url: release[:html_url],
        published_at: release[:published_at],
        checked_at: Time.current.iso8601
      }, expires_in: 25.hours)

      Rails.logger.info("[UpdateCheck] New version available: #{release[:version]} (current: #{current})")
    else
      Rails.cache.delete("hivemind:update_available")
      Rails.logger.info("[UpdateCheck] Up to date: #{current}")
    end
  rescue StandardError => e
    Rails.logger.warn("[UpdateCheck] Failed: #{e.message}")
  end

  private

  def update_check_enabled?
    ENV.fetch("UPDATE_CHECK_ENABLED", "true") != "false"
  end
end
