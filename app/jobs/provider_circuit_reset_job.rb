# frozen_string_literal: true

require "net/http"

# Tells the sdk-proxy to clear its in-process circuit for a credential.
#
# The proxy keeps its own breaker (it is the thing holding the subprocesses),
# so a human fixing an account has to clear both sides. Runs as a job rather
# than inline so an unreachable proxy never blocks the provider-edit request.
class ProviderCircuitResetJob < ApplicationJob
  queue_as :system

  # Best-effort: the proxy recovers on its own cooldown if this never lands.
  discard_on StandardError

  TIMEOUT = 2

  def perform(provider = "anthropic")
    return unless provider.to_s == "anthropic"

    uri = URI("#{Providers::AnthropicAdapter::SDK_PROXY_URL}/admin/circuit/reset")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Post.new(uri.path, {
      "Content-Type" => "application/json",
      "X-Internal-Secret" => ENV.fetch("INTERNAL_API_SECRET", "")
    })
    request.body = "{}"

    response = http.request(request)
    Rails.logger.info("[CircuitBreaker] sdk-proxy circuit reset -> HTTP #{response.code}")
  end
end
