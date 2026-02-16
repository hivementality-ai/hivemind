# frozen_string_literal: true

module Platform
  # Get Docker container statuses
  class ContainerStatus
    SERVICES = %w[rails sidekiq postgres redis browser workspace connector].freeze

    def self.call
      new.call
    end

    def call
      statuses = SERVICES.map do |service|
        {
          name: service,
          status: get_container_status(service),
          health: get_container_health(service)
        }
      end

      ServiceResponse.success(data: { services: statuses })
    rescue => e
      ServiceResponse.failure(error: "Failed to get container status: #{e.message}")
    end

    private

    def get_container_status(service)
      if production_environment?
        check_docker_status(service)
      else
        check_development_status(service)
      end
    end

    def check_docker_status(service)
      # Get container status via docker compose
      output = `docker compose ps #{service} 2>&1`

      if output.include?("Up")
        :running
      elsif output.include?("Exit")
        :stopped
      else
        :unknown
      end
    rescue
      :unknown
    end

    def check_development_status(service)
      # In development, check if process is likely running
      case service
      when "rails"
        port_open?(3000) ? :running : :stopped
      when "postgres"
        port_open?(5432) ? :running : :stopped
      when "redis"
        port_open?(6379) ? :running : :stopped
      else
        :unknown
      end
    end

    def get_container_health(service)
      if production_environment?
        check_docker_health(service)
      else
        :healthy
      end
    end

    def check_docker_health(service)
      output = `docker inspect --format='{{.State.Health.Status}}' hivemind-#{service} 2>&1`

      case output.strip
      when "healthy"
        :healthy
      when "unhealthy"
        :unhealthy
      when "starting"
        :starting
      else
        :unknown
      end
    rescue
      :unknown
    end

    def port_open?(port)
      Socket.tcp("localhost", port, connect_timeout: 1) { true }
    rescue
      false
    end

    def production_environment?
      ENV["RAILS_ENV"] == "production" || ENV["DOCKER_ENV"] == "true"
    end
  end
end
