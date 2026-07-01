# frozen_string_literal: true

require "net/http"
require "uri"

# POSTs a signed JSON event payload to one WebhookEndpoint. Records delivery
# outcome on the endpoint and retries transient failures with backoff.
class WebhookDeliveryJob < ApplicationJob
  queue_as :system

  # ponytail: ActiveJob exponential backoff, 5 attempts. The endpoint auto-disables
  # after MAX_FAILURES consecutive failures (recorded below). Upgrade to a
  # dead-letter table / per-endpoint circuit breaker only if delivery volume or
  # failure-replay needs it — retry_on covers the common case.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  TIMEOUT = 10

  class DeliveryError < StandardError; end

  def perform(endpoint_id, event_type, data)
    endpoint = WebhookEndpoint.find_by(id: endpoint_id)
    return unless endpoint&.enabled?

    body = JSON.generate(event: event_type, data: data, timestamp: Time.current.iso8601)
    # Same scheme as inbound verify_hmac_signature: hex HMAC-SHA256 of the raw body.
    signature = OpenSSL::HMAC.hexdigest("sha256", endpoint.secret, body)

    response = post(endpoint.url, body, signature, event_type)
    status = response.code.to_i

    if status >= 400
      endpoint.record_failure!(status)
      raise DeliveryError, "delivery to endpoint #{endpoint.id} failed: HTTP #{status}"
    end

    endpoint.record_success!(status)
  rescue DeliveryError
    raise # failure already recorded above; re-raise so retry_on backs off
  rescue StandardError
    # Network/transport error (timeout, DNS, TLS). Record then let retry_on retry.
    endpoint&.record_failure!
    raise
  end

  private

  def post(url, body, signature, event_type)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Hivemind-Signature"] = signature
    request["X-Hivemind-Event"] = event_type
    request["User-Agent"] = "Hivemind/1.0"
    request.body = body

    http.request(request)
  end
end
