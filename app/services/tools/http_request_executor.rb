# frozen_string_literal: true

module Tools
  class HttpRequestExecutor
    # Executes HTTP requests, optionally scoped to an ApiIntegration.
    #
    # Input parameters:
    #   action:         "request" (direct) or "list_apis" or "list_endpoints"
    #   integration:    Name of the ApiIntegration (optional — if omitted, makes a raw request)
    #   method:         HTTP method (GET, POST, PUT, PATCH, DELETE, HEAD)
    #   url:            Full URL (for raw requests) or endpoint path (for integration requests)
    #   path:           Alias for url when using an integration
    #   headers:        Additional headers (Hash)
    #   query:          Query parameters (Hash)
    #   body:           Request body (String or Hash — Hash gets JSON-encoded)
    #   timeout:        Request timeout in seconds (default: 30)
    #   operation_id:   Match endpoint by operation_id instead of path (integration mode)

    MAX_RESPONSE_SIZE = 1_048_576 # 1MB
    ALLOWED_METHODS = %w[GET POST PUT PATCH DELETE HEAD OPTIONS].freeze

    def initialize(input:, config: {}, agent: nil)
      @input = input.is_a?(Hash) ? input : {}
      @config = config || {}
      @agent = agent
    end

    def call
      action = @input["action"] || "request"

      case action
      when "list_apis"      then list_apis
      when "list_endpoints" then list_endpoints
      when "request"        then execute_request
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Use: request, list_apis, list_endpoints")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "HTTP request failed: #{e.message}")
    end

    private

    # ─── List APIs ────────────────────────────────────────────────

    def list_apis
      apis = ApiIntegration.enabled.map do |api|
        {
          name: api.name,
          base_url: api.base_url,
          description: api.description,
          endpoints_count: api.endpoints&.size || 0,
          auth_type: api.auth_type
        }
      end

      ServiceResponse.success(data: { output: JSON.pretty_generate(apis) })
    end

    # ─── List Endpoints ───────────────────────────────────────────

    def list_endpoints
      name = @input["integration"]
      return ServiceResponse.failure(error: "Specify 'integration' name") if name.blank?

      api = ApiIntegration.enabled.find_by("LOWER(name) = ?", name.downcase)
      return ServiceResponse.failure(error: "API '#{name}' not found") unless api

      summary = api.endpoints.map do |ep|
        line = "#{ep['method']&.upcase} #{ep['path']}"
        line += " — #{ep['summary']}" if ep["summary"].present?
        if ep["parameters"]&.any?
          params = ep["parameters"].map { |p| "#{p['name']}#{p['required'] ? '*' : ''} (#{p['in']})" }
          line += "\n  Params: #{params.join(', ')}"
        end
        if ep["request_body"]
          line += "\n  Body: #{ep['request_body']['content_type']} (#{ep['request_body']['required'] ? 'required' : 'optional'})"
        end
        line
      end

      output = "API: #{api.name} (#{api.base_url})\n#{api.description}\n\nEndpoints:\n#{summary.join("\n\n")}"
      ServiceResponse.success(data: { output: output })
    end

    # ─── Execute Request ──────────────────────────────────────────

    def execute_request
      if @input["integration"].present?
        execute_integration_request
      else
        execute_raw_request
      end
    end

    def execute_integration_request
      api = ApiIntegration.enabled.find_by("LOWER(name) = ?", @input["integration"].downcase)
      return ServiceResponse.failure(error: "API '#{@input['integration']}' not found") unless api

      # Find endpoint
      endpoint = if @input["operation_id"].present?
                   api.find_endpoint(operation_id: @input["operation_id"])
      else
                   path = @input["path"] || @input["url"]
                   method = (@input["method"] || "GET").downcase
                   api.find_endpoint(path: path, method: method)
      end

      method = (@input["method"] || endpoint&.dig("method") || "GET").upcase
      path = @input["path"] || @input["url"] || endpoint&.dig("path")

      return ServiceResponse.failure(error: "No path specified and endpoint not found") if path.blank?

      # Build full URL
      full_url = if path.start_with?("http")
                   path
      else
                   "#{api.base_url.chomp('/')}#{path}"
      end

      # Interpolate path parameters
      (@input["query"] || {}).each do |key, value|
        if full_url.include?("{#{key}}")
          full_url = full_url.gsub("{#{key}}", value.to_s)
        end
      end

      # Build headers
      headers = api.request_headers
                   .merge("Content-Type" => "application/json", "Accept" => "application/json")
                   .merge(@input["headers"] || {})

      timeout = [ @input["timeout"]&.to_i || api.timeout_seconds, 120 ].min

      make_request(
        method: method,
        url: full_url,
        headers: headers,
        query: @input["query"],
        body: @input["body"],
        timeout: timeout,
        max_bytes: api.max_response_bytes || MAX_RESPONSE_SIZE
      )
    end

    def execute_raw_request
      url = @input["url"]
      return ServiceResponse.failure(error: "URL is required for raw requests") if url.blank?

      method = (@input["method"] || "GET").upcase
      return ServiceResponse.failure(error: "Invalid method: #{method}") unless ALLOWED_METHODS.include?(method)

      # Security: block private IPs in production
      if Rails.env.production? && private_ip?(url)
        return ServiceResponse.failure(error: "Requests to private IPs are not allowed")
      end

      headers = (@input["headers"] || {}).merge("Accept" => "application/json")
      timeout = [ @input["timeout"]&.to_i || 30, 120 ].min

      make_request(
        method: method,
        url: url,
        headers: headers,
        query: @input["query"],
        body: @input["body"],
        timeout: timeout,
        max_bytes: MAX_RESPONSE_SIZE
      )
    end

    # ─── HTTP Client ──────────────────────────────────────────────

    def make_request(method:, url:, headers: {}, query: nil, body: nil, timeout: 30, max_bytes: MAX_RESPONSE_SIZE)
      uri = URI.parse(url)

      # Add query params
      if query.is_a?(Hash) && query.any?
        existing = URI.decode_www_form(uri.query || "").to_h
        uri.query = URI.encode_www_form(existing.merge(query))
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = [ timeout, 30 ].min
      http.read_timeout = timeout

      request_class = case method
      when "GET"     then Net::HTTP::Get
      when "POST"    then Net::HTTP::Post
      when "PUT"     then Net::HTTP::Put
      when "PATCH"   then Net::HTTP::Patch
      when "DELETE"  then Net::HTTP::Delete
      when "HEAD"    then Net::HTTP::Head
      when "OPTIONS" then Net::HTTP::Options
      else return ServiceResponse.failure(error: "Unsupported method: #{method}")
      end

      req = request_class.new(uri)
      headers.each { |k, v| req[k] = v.to_s }

      if body.present? && %w[POST PUT PATCH].include?(method)
        req.body = body.is_a?(Hash) ? body.to_json : body.to_s
        req["Content-Type"] ||= "application/json"
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = http.request(req)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i

      response_body = response.body.to_s
      truncated = response_body.bytesize > max_bytes
      response_body = response_body.byteslice(0, max_bytes) if truncated

      output = {
        status: response.code.to_i,
        headers: response.each_header.to_h,
        body: try_parse_json(response_body),
        duration_ms: duration_ms,
        truncated: truncated,
        url: uri.to_s,
        method: method
      }

      ServiceResponse.success(data: { output: JSON.pretty_generate(output) })
    rescue Net::OpenTimeout, Net::ReadTimeout
      ServiceResponse.failure(error: "Request timed out after #{timeout}s")
    rescue SocketError, Errno::ECONNREFUSED => e
      ServiceResponse.failure(error: "Connection failed: #{e.message}")
    end

    # ─── Helpers ──────────────────────────────────────────────────

    def try_parse_json(str)
      JSON.parse(str)
    rescue JSON::ParserError
      str.truncate(10_000)
    end

    def private_ip?(url)
      host = URI.parse(url).host
      return false unless host

      ip = IPAddr.new(host) rescue nil
      return false unless ip

      private_ranges = [
        IPAddr.new("10.0.0.0/8"),
        IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.168.0.0/16"),
        IPAddr.new("127.0.0.0/8"),
        IPAddr.new("169.254.0.0/16")
      ]

      private_ranges.any? { |range| range.include?(ip) }
    rescue StandardError
      false
    end
  end
end
