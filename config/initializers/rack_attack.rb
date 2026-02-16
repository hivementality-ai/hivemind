# frozen_string_literal: true

class Rack::Attack
  # Throttle all requests by IP (300 requests per 5 minutes)
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Throttle login attempts by IP (5 attempts per 20 seconds)
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email (5 attempts per minute)
  throttle("logins/email", limit: 5, period: 60.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  # Throttle API token auth (10 attempts per minute)
  throttle("api/ip", limit: 10, period: 60.seconds) do |req|
    if req.path.start_with?("/api/") && req.env["HTTP_AUTHORIZATION"].blank?
      req.ip
    end
  end

  # Throttle webhook endpoints (60 per minute per IP)
  throttle("webhooks/ip", limit: 60, period: 60.seconds) do |req|
    if req.path.start_with?("/webhooks/")
      req.ip
    end
  end

  # Block IPs that have been banned
  blocklist("block/banned") do |req|
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 20, findtime: 1.minute, bantime: 1.hour) do
      req.path == "/users/sign_in" && req.post?
    end
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |_request|
    [ 429, { "Content-Type" => "application/json" }, [ { error: "Rate limit exceeded" }.to_json ] ]
  end
end
