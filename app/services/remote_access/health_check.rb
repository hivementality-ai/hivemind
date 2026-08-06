# frozen_string_literal: true

require "faraday"
require "websocket-client-simple"
require "uri"
require "securerandom"

module RemoteAccess
  # Performs a real WebSocket upgrade handshake against a URL and reports
  # whether the connection opened. Isolated from HealthCheck so specs can
  # stub the network boundary without reaching into EventMachine internals.
  class WebSocketProbe
    def self.call(url, timeout: 10)
      new(url, timeout:).call
    end

    def initialize(url, timeout: 10)
      @url = url
      @timeout = timeout
    end

    def call
      result = { connected: false, error: nil }
      mutex = Mutex.new
      cv = ConditionVariable.new
      done = false

      ws = WebSocket::Client::Simple.connect(url)

      ws.on :open do
        mutex.synchronize do
          result[:connected] = true
          done = true
          cv.signal
        end
      end

      ws.on :error do |e|
        mutex.synchronize do
          result[:error] ||= e.respond_to?(:message) ? e.message : e.to_s
          done = true
          cv.signal
        end
      end

      ws.on :close do
        mutex.synchronize do
          done = true
          cv.signal
        end
      end

      mutex.synchronize do
        cv.wait(mutex, timeout) unless done
      end

      begin
        ws.close
      rescue StandardError
        nil
      end

      if result[:connected]
        { ok: true }
      else
        { ok: false, error: result[:error] || "WebSocket handshake timed out after #{timeout}s" }
      end
    rescue StandardError => e
      { ok: false, error: e.message }
    end

    private

    attr_reader :url, :timeout
  end

  # Verifies a public URL actually reaches this hivemind instance:
  #   1. HTTP health check — GET the URL, expect a non-5xx response.
  #   2. WebSocket handshake against `<url>/cable` — a real upgrade request,
  #      not just a TCP connect, so a misconfigured reverse proxy that drops
  #      the Upgrade header shows up as a failure here instead of at
  #      first-agent-connect time.
  #
  # Returns a ServiceResponse whose data is a hash with per-check results so
  # the wizard/status card can show clear pass/fail for each:
  #   { http: { ok:, status:, error: }, websocket: { ok:, error: } }
  class HealthCheck
    HTTP_TIMEOUT = 10
    WS_TIMEOUT = 10

    def self.call(url)
      new(url).call
    end

    def initialize(url)
      @url = url.to_s.strip.chomp("/")
    end

    def call
      return ServiceResponse.failure(error: "No URL provided") if url.blank?
      return ServiceResponse.failure(error: "URL must be http(s)") unless valid_url?

      http_result = check_http
      ws_result = check_websocket

      overall = { http: http_result, websocket: ws_result }
      ok = http_result[:ok] && ws_result[:ok]

      if ok
        ServiceResponse.success(data: overall)
      else
        ServiceResponse.failure(error: build_error_summary(overall), payload: overall)
      end
    end

    private

    attr_reader :url

    def valid_url?
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def check_http
      response = connection.get(url)
      if response.status.to_i < 500
        { ok: true, status: response.status }
      else
        { ok: false, status: response.status, error: "HTTP #{response.status}" }
      end
    rescue Faraday::Error => e
      { ok: false, status: nil, error: e.message }
    rescue StandardError => e
      { ok: false, status: nil, error: e.message }
    end

    def check_websocket
      WebSocketProbe.call(websocket_url, timeout: WS_TIMEOUT)
    rescue StandardError => e
      { ok: false, error: e.message }
    end

    def websocket_url
      uri = URI.parse(url)
      scheme = uri.scheme == "https" ? "wss" : "ws"
      port_suffix = (uri.port && uri.port != uri.default_port) ? ":#{uri.port}" : ""
      "#{scheme}://#{uri.host}#{port_suffix}/cable"
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.options.timeout = HTTP_TIMEOUT
        f.options.open_timeout = HTTP_TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    def build_error_summary(results)
      parts = []
      parts << "HTTP check failed: #{results[:http][:error]}" unless results[:http][:ok]
      parts << "WebSocket check failed: #{results[:websocket][:error]}" unless results[:websocket][:ok]
      parts.join("; ")
    end
  end
end
