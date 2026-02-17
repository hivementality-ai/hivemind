# frozen_string_literal: true

class GithubReleaseChecker
  REPO = "hivementality-ai/hivemind"
  CACHE_KEY = "hivemind:latest_release"
  CACHE_TTL = 25.hours

  class << self
    def latest_release
      cached = Rails.cache.read(CACHE_KEY)
      return cached if cached.present?

      release = fetch_latest_release
      Rails.cache.write(CACHE_KEY, release, expires_in: CACHE_TTL) if release
      release
    end

    def update_available?
      release = latest_release
      return false unless release

      current = Hivemind::VERSION
      return false if current == "dev"

      newer?(release[:version], current)
    end

    def update_info
      release = latest_release
      return nil unless release

      current = Hivemind::VERSION
      is_newer = current != "dev" && newer?(release[:version], current)

      {
        current: current,
        latest: release[:version],
        update_available: is_newer,
        breaking_changes: release[:breaking_changes],
        changelog_url: release[:html_url],
        published_at: release[:published_at],
        last_checked: Time.current.iso8601
      }
    end

    private

    def fetch_latest_release
      uri = URI("https://api.github.com/repos/#{REPO}/releases/latest")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 5

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["User-Agent"] = "Hivemind/#{Hivemind::VERSION}"

      response = http.request(request)
      return nil unless response.code == "200"

      data = JSON.parse(response.body)
      version = data["tag_name"]&.delete_prefix("v")

      {
        version: version,
        html_url: data["html_url"],
        published_at: data["published_at"],
        breaking_changes: breaking_changes?(data["body"]),
        body: data["body"]
      }
    rescue StandardError => e
      Rails.logger.warn("[GithubReleaseChecker] Failed to check for updates: #{e.message}")
      nil
    end

    def breaking_changes?(body)
      return false if body.blank?

      body.match?(/breaking.change|⚠️|BREAKING/i)
    end

    def newer?(latest, current)
      return false if latest.blank? || current.blank?

      latest_parts = latest.split(".").map(&:to_i)
      current_parts = current.split(".").map(&:to_i)

      (latest_parts <=> current_parts) == 1
    rescue StandardError
      false
    end
  end
end
