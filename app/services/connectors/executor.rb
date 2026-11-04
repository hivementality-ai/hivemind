# frozen_string_literal: true

require "base64"
require "erb"
require "json"
require "net/http"
require "uri"

module Connectors
  # Runs one operation of a Connector: fills the path, splits the remaining params
  # into query or body, injects auth read from the vault, and enforces timeouts and
  # a response size cap. Never follows redirects and never reaches metadata addresses.
  class Executor
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    WRITE_TIMEOUT = 20
    MAX_RESPONSE_BYTES = 1_048_576
    BODY_METHODS = %w[POST PUT PATCH].freeze

    # @param connector [Connector]
    # @param operation [String] operation name
    # @param params [Hash] arguments for the operation
    # @param agent [Agent, nil] agent running the call, for vault scope and egress policy
    # @return [ServiceResponse] success with +data[:output]+, +:status+, +:truncated+
    def self.call(connector:, operation:, params: {}, agent: nil)
      new(connector:, operation:, params:, agent:).call
    end

    def initialize(connector:, operation:, params:, agent:)
      @connector = connector
      @operation_name = operation.to_s
      @params = (params || {}).to_h.stringify_keys
      @agent = agent
      @secrets = []
    end

    def call
      return ServiceResponse.failure(error: "Connector #{@connector.slug} is disabled") unless @connector.enabled?

      operation = @connector.operation(@operation_name)
      return ServiceResponse.failure(error: "Unknown operation #{@operation_name} on #{@connector.slug}") unless operation

      missing = required_params(operation).reject { |name| @params.key?(name) }
      return ServiceResponse.failure(error: "Missing required params: #{missing.join(', ')}") if missing.any?

      perform(operation)
    rescue Connectors::AddressGuard::Blocked, ArgumentError => e
      ServiceResponse.failure(error: e.message)
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError => e
      Connectors::Health.record_failure(@connector, @operation_name, :transient)
      ServiceResponse.failure(error: "Request failed: #{e.class.name.demodulize}")
    end

    private

    def perform(operation)
      verb = operation["method"].to_s.upcase
      uri, remaining = build_uri(operation)
      query = verb.in?(BODY_METHODS) ? {} : remaining
      body = verb.in?(BODY_METHODS) ? remaining : nil

      headers = { "Accept" => "application/json" }
      apply_auth!(headers, query)
      uri.query = URI.encode_www_form(query) if query.any?

      egress = @agent && NetworkEgress::PolicyCheck.call(agent: @agent, url: uri.to_s)
      return ServiceResponse.failure(error: "Egress blocked: #{egress.reason}") if egress && !egress.allowed?

      address = Connectors::AddressGuard.resolve!(uri.host).first
      send_request(uri, address, verb, headers, body)
    end

    def required_params(operation)
      Array(operation.dig("params", "required")).map(&:to_s)
    end

    def build_uri(operation)
      remaining = @params.dup
      path = operation["path"].gsub(Connector::PATH_PLACEHOLDER) do
        param = Regexp.last_match(1)
        value = remaining.delete(param).to_s
        raise ArgumentError, "Path param #{param} is invalid" if value.empty? || %w[. ..].include?(value)

        ERB::Util.url_encode(value)
      end

      base = URI.parse(@connector.base_url)
      uri = base.dup
      uri.path = "#{base.path.chomp('/')}#{path}"
      raise ArgumentError, "Operation path escapes the base URL" unless uri.host == base.host && uri.path.start_with?(base.path.chomp("/"))

      [ uri, remaining ]
    end

    def apply_auth!(headers, query)
      config = @connector.auth_config
      case @connector.auth_scheme
      when "api_key_header" then headers[config["header_name"]] = secret(config["secret"])
      when "api_key_query" then query[config["param_name"]] = secret(config["secret"])
      when "bearer" then headers["Authorization"] = "Bearer #{secret(config['secret'])}"
      when "oauth2" then headers["Authorization"] = "Bearer #{secret(config['access_token'])}"
      when "basic"
        credentials = "#{secret(config['username'])}:#{secret(config['password'])}"
        headers["Authorization"] = "Basic #{Base64.strict_encode64(credentials)}"
      end
    end

    def secret(reference)
      result = Vault::Reference.resolve(reference, agent: @agent)
      raise ArgumentError, result.error unless result.success?

      value = result.data[:value].to_s
      raise ArgumentError, "Secret #{reference} is empty or malformed" if value.empty? || value.match?(/[\r\n]/)

      @secrets << value
      value
    end

    def send_request(uri, address, verb, headers, body)
      request = Net::HTTP.const_get(verb.capitalize).new(uri.request_uri, headers)
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = address
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.write_timeout = WRITE_TIMEOUT

      status, text, truncated = http.start { read_response(http, request) }
      respond(status, scrub(text), truncated)
    end

    def read_response(http, request)
      buffer = +""
      truncated = false
      status = nil
      http.request(request) do |response|
        status = response.code.to_i
        response.read_body do |chunk|
          buffer << chunk
          next if buffer.bytesize <= MAX_RESPONSE_BYTES

          truncated = true
          break
        end
      end
      [ status, buffer.byteslice(0, MAX_RESPONSE_BYTES).to_s.scrub, truncated ]
    end

    def respond(status, text, truncated)
      if status.between?(200, 299)
        Connectors::Health.record_success(@connector, @operation_name)
        return ServiceResponse.success(data: { output: text, status:, truncated: })
      end

      ServiceResponse.failure(error: "HTTP #{status}: #{text.truncate(500)}#{repair_hint(status, text)}")
    end

    def repair_hint(status, text)
      kind = Connectors::Health.classify(status, text)
      count = Connectors::Health.record_failure(@connector, @operation_name, kind, status:)
      return "" unless kind == :definition && Connectors::Health.repair_suggested?(count)

      "\n#{Connectors::Health::HINT}"
    end

    def scrub(text)
      @secrets.select { |s| s.length >= 4 }.reduce(text) { |out, s| out.gsub(s, "[REDACTED]") }
    end
  end
end
