# frozen_string_literal: true

# Redis.current was removed in redis-rb 5.x
# Provide a global accessor for services that need shared Redis access
class Redis
  def self.current
    @current ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  end
end
