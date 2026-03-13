# frozen_string_literal: true

require "socket"

module Platform
  class ServiceHealth
    def self.call
      new.call
    end

    def call
      db = db_connected?
      redis = redis_connected?

      services = [
        { name: "Web Server", description: "HTTP & WebSocket", running: true, status: "Running" },
        { name: "Job Workers", description: "Background processing", running: sidekiq_running?, status: sidekiq_running? ? "Running" : "Down" },
        { name: "Database", description: "Primary data store", running: db, status: db ? "Healthy" : "Down" },
        { name: "Cache", description: "Jobs queue & real-time", running: redis, status: redis ? "Healthy" : "Down" },
        { name: "Browser", description: "Headless web automation", running: browser_running?, status: browser_running? ? "Running" : "Down" },
        { name: "Workspace", description: "Sandboxed execution", running: workspace_running?, status: workspace_running? ? "Running" : "Down" },
        { name: "Connector", description: "Messaging bridge", running: connector_running?, status: connector_running? ? "Running" : "Down" }
      ]

      providers = ProviderConfig.all.map do |config|
        { config: config, status: check_provider(config) }
      end

      ServiceResponse.success(data: {
        services: services,
        providers: providers,
        db_connected: db,
        redis_connected: redis
      })
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end

    private

    def db_connected?
      ActiveRecord::Base.connection.active?
    rescue StandardError
      false
    end

    def redis_connected?
      Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379").ping == "PONG"
    rescue StandardError
      false
    end

    def sidekiq_running?
      Sidekiq::ProcessSet.new.size > 0
    rescue StandardError
      false
    end

    def browser_running?
      tcp_check("browser", 3001)
    end

    def workspace_running?
      File.directory?("/workspace")
    rescue StandardError
      false
    end

    def connector_running?
      tcp_check("connector", 3002)
    end

    def tcp_check(host, port, timeout = 2)
      Socket.tcp(host, port, connect_timeout: timeout) { true }
    rescue StandardError
      false
    end

    def check_provider(config)
      case config.adapter_type
      when "ollama"
        adapter = Providers::OllamaAdapter.new(config: config)
        result = adapter.models
        result.success? ? { ok: true, models: result.data[:models].size } : { ok: false }
      when "anthropic", "openai"
        { ok: config.enabled?, note: config.enabled? ? "Key configured" : "Disabled" }
      else
        { ok: false }
      end
    rescue StandardError
      { ok: false }
    end
  end
end
