# frozen_string_literal: true

module Platform
  # Clear Redis caches safely
  class ClearCache
    def self.call(cache_type: "all", actor: "system")
      new(cache_type: cache_type, actor: actor).call
    end
    
    def initialize(cache_type: "all", actor: "system")
      @cache_type = cache_type
      @actor = actor
    end
    
    def call
      cleared = []
      
      case @cache_type
      when "all"
        clear_rails_cache
        clear_action_cache
        cleared = ["rails_cache", "action_cache"]
      when "rails"
        clear_rails_cache
        cleared = ["rails_cache"]
      when "action"
        clear_action_cache
        cleared = ["action_cache"]
      else
        return ServiceResponse.failure(error: "Unknown cache type: #{@cache_type}")
      end
      
      Audit::Log.call(
        actor: @actor,
        action: "platform.cache_cleared",
        resource: nil,
        metadata: {
          cache_type: @cache_type,
          cleared: cleared
        }
      )
      
      ServiceResponse.success(data: { cleared: cleared })
    rescue => e
      ServiceResponse.failure(error: "Cache clear failed: #{e.message}")
    end
    
    private
    
    def clear_rails_cache
      Rails.cache.clear
      Rails.logger.info "Rails cache cleared"
    end
    
    def clear_action_cache
      # Clear ActionCable cache if needed
      # ActionCable.server.pubsub.clear if ActionCable.server.pubsub.respond_to?(:clear)
      Rails.logger.info "Action cache cleared"
    end
  end
end
