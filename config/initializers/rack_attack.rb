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

  # Throttle unauthenticated API requests by IP (10 attempts per minute)
  throttle("api/ip", limit: 10, period: 60.seconds) do |req|
    if req.path.start_with?("/api/") && req.env["HTTP_AUTHORIZATION"].blank?
      req.ip
    end
  end

  # Throttle authenticated API requests by token (60 req/min)
  throttle("api/token", limit: 60, period: 60.seconds) do |req|
    if req.path.start_with?("/api/") && req.env["HTTP_AUTHORIZATION"].present?
      req.env["HTTP_AUTHORIZATION"].to_s.gsub(/^Bearer /, "")
    end
  end

  # Throttle chat messages (30 req/min per IP+session)
  throttle("messages/session", limit: 30, period: 60.seconds) do |req|
    if req.post? && req.path.match?(%r{^/(sessions|team_chats)/\d+/message$})
      "#{req.ip}:#{req.path}"
    end
  end

  # Throttle webhook endpoints (120 per minute per IP)
  throttle("webhooks/ip", limit: 120, period: 60.seconds) do |req|
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

  # Include Retry-After header on throttled responses
  Rack::Attack.throttled_response_retry_after_header = true

  # Custom response for throttled requests with rate limit headers
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]
    retry_after = match_data[:period] - (now % match_data[:period])

    headers = {
      "Content-Type" => "application/json",
      "Retry-After" => retry_after.to_s,
      "X-RateLimit-Limit" => match_data[:limit].to_s,
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => (now + retry_after).to_i.to_s
    }

    [ 429, headers, [ { error: "Rate limit exceeded. Retry after #{retry_after} seconds." }.to_json ] ]
  end
end
