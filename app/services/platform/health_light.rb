# frozen_string_literal: true

require "net/http"
require "timeout"

module Platform
  # The header health light: one colour and a short plain-English list.
  #
  # Page loads only ever read the cached snapshot. A stale or missing snapshot
  # queues {HealthLightRefreshJob}, which runs the checks, each under a hard
  # deadline. Green means everything works, amber means something optional is
  # down, red means a check the app cannot run without is down.
  class HealthLight
    CACHE_KEY = "hivemind:health_light"
    LOCK_KEY = "hivemind:health_light:refreshing"
    FRESH_FOR = 60.seconds
    KEEP_FOR = 10.minutes
    CHECK_TIMEOUT = 2

    Check = Struct.new(:key, :label, :ok, :detail, :critical, keyword_init: true)

    class << self
      # Rolls checks up into a light colour.
      #
      # @param checks [Array<Check>]
      # @return [Symbol] :green, :amber or :red
      def rollup(checks)
        failing = checks.reject(&:ok)
        return :green if failing.empty?

        failing.any?(&:critical) ? :red : :amber
      end

      # Reads the cached snapshot without running any check, and queues a
      # refresh when it is missing or older than {FRESH_FOR}.
      #
      # @return [Hash, nil] +{ status:, checks:, checked_at: }+ or nil before the first refresh
      def snapshot
        cached = Rails.cache.read(CACHE_KEY)
        refresh_later if cached.nil? || Time.current - cached[:checked_at] > FRESH_FOR
        cached
      rescue StandardError
        nil
      end

      # Runs every check and stores the result.
      #
      # @return [Hash] the stored snapshot
      def refresh!
        checks = [ claude_check, studio_check, redis_check, sidekiq_check ].compact
        result = {
          status: rollup(checks),
          checks: checks.map(&:to_h),
          checked_at: Time.current
        }
        Rails.cache.write(CACHE_KEY, result, expires_in: KEEP_FOR)
        result
      end

      private

      def refresh_later
        return unless Rails.cache.write(LOCK_KEY, true, expires_in: 30.seconds, unless_exist: true)

        HealthLightRefreshJob.perform_later
      end

      def claude_check
        return unless Providers::AnthropicAdapter.sdk_proxy_enabled?

        health = fetch_json("#{Providers::AnthropicAdapter::SDK_PROXY_URL}/health")
        if health.nil?
          Check.new(key: "claude", label: "Claude", ok: false, detail: "not reachable", critical: true)
        elsif health["degraded"]
          Check.new(key: "claude", label: "Claude", ok: false, detail: "needs attention, calls are paused", critical: true)
        else
          Check.new(key: "claude", label: "Claude", ok: true, detail: "working", critical: true)
        end
      end

      def studio_check
        config = ProviderConfig.enabled_providers.find_by(adapter_type: "ollama")
        return unless config

        url = config.base_url.presence || ENV.fetch("OLLAMA_URL", "http://host.docker.internal:11434")
        ok = !fetch_json("#{url.chomp('/')}/api/tags").nil?
        Check.new(key: "studio", label: "Studio brain", ok: ok, detail: ok ? "working" : "not reachable", critical: false)
      end

      def redis_check
        ok = within_deadline { ServiceHealth.new.redis_connected? }
        Check.new(key: "redis", label: "Redis", ok: ok, detail: ok ? "working" : "not reachable", critical: true)
      end

      def sidekiq_check
        ok = within_deadline { ServiceHealth.new.sidekiq_running? }
        Check.new(key: "sidekiq", label: "Background jobs", ok: ok, detail: ok ? "working" : "not running", critical: true)
      end

      # GETs a JSON endpoint, giving up after {CHECK_TIMEOUT} seconds in total.
      #
      # @return [Hash, nil] parsed body, or nil on any failure or timeout
      def fetch_json(url)
        within_deadline(nil) do
          uri = URI(url)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                         open_timeout: CHECK_TIMEOUT, read_timeout: CHECK_TIMEOUT) do |http|
            http.get(uri.request_uri)
          end
          response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
        end
      end

      def within_deadline(fallback = false, &block)
        Timeout.timeout(CHECK_TIMEOUT, &block)
      rescue StandardError
        fallback
      end
    end
  end
end
