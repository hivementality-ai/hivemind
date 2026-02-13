# frozen_string_literal: true

module Tools
  class GatewayExecutor < BaseExecutor
    # Platform management: status, restart services, clear cache
    def call
      action = input["action"].to_s.strip

      case action
      when "status"
        platform_status
      when "restart"
        restart_service(input["service"].to_s.strip)
      when "config"
        show_config
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: status, restart, config")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Gateway error: #{e.message}")
    end

    private

    def platform_status
      output = []
      output << "🐝 Hivemind Platform Status"
      output << "Ruby: #{RUBY_VERSION} | Rails: #{Rails.version}"
      output << "Environment: #{Rails.env}"
      output << ""

      # DB
      db_ok = ActiveRecord::Base.connection.active? rescue false
      output << "PostgreSQL: #{db_ok ? '✅ Connected' : '❌ Down'}"

      # Redis
      redis_ok = begin
        Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379").ping == "PONG"
      rescue StandardError
        false
      end
      output << "Redis: #{redis_ok ? '✅ Connected' : '❌ Down'}"

      # Counts
      output << ""
      output << "Agents: #{Agent.visible.count} (#{Agent.visible.enabled.count} enabled)"
      output << "Teams: #{Team.count}"
      output << "Sessions: #{Session.count}"
      output << "Tools: #{Tool.where(enabled: true).count}"
      output << "Usage Records: #{UsageRecord.count}"

      # Providers
      output << ""
      output << "Providers:"
      ProviderConfig.all.each do |p|
        output << "  #{p.adapter_type}: #{p.enabled? ? '✅' : '⏸️'}"
      end

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    end

    def restart_service(service)
      allowed = %w[rails sidekiq]
      return ServiceResponse.failure(error: "Can only restart: #{allowed.join(", ")}") unless allowed.include?(service)

      # Touch tmp/restart.txt for Puma, or enqueue a restart job
      if service == "rails"
        FileUtils.touch(Rails.root.join("tmp", "restart.txt"))
        ServiceResponse.success(data: { output: "Rails restart triggered (Puma will pick up on next request)", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "Sidekiq restart not supported from within the app. Use Docker CLI.", exit_code: 0 })
      end
    end

    def show_config
      output = []
      output << "Database: #{ActiveRecord::Base.connection.current_database}"
      output << "Redis: #{ENV["REDIS_URL"] || "not set"}"
      output << "Sidekiq Cron Jobs:"

      if defined?(Sidekiq::Cron)
        Sidekiq::Cron::Job.all.each do |j|
          output << "  #{j.name} — #{j.cron} (#{j.klass})"
        end
      end

      output << ""
      output << "Settings:"
      Setting.all.each do |s|
        val = s.value.to_s.truncate(60)
        output << "  #{s.key}: #{val}"
      end

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    end
  end
end
