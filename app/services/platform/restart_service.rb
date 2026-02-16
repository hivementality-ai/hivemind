# frozen_string_literal: true

module Platform
  # Restart a Docker service
  class RestartService
    ALLOWED_SERVICES = %w[workspace browser connector].freeze
    FORBIDDEN_SERVICES = %w[rails postgres redis].freeze

    def self.call(service_name:, actor: "system")
      new(service_name: service_name, actor: actor).call
    end

    def initialize(service_name:, actor: "system")
      @service_name = service_name
      @actor = actor
    end

    def call
      # Safety check
      if FORBIDDEN_SERVICES.include?(@service_name)
        return ServiceResponse.failure(
          error: "Cannot restart #{@service_name} - safety restriction"
        )
      end

      unless ALLOWED_SERVICES.include?(@service_name)
        return ServiceResponse.failure(
          error: "Unknown service: #{@service_name}"
        )
      end

      # Execute restart
      result = restart_container

      if result[:success]
        Audit::Log.call(
          actor: @actor,
          action: "platform.service_restarted",
          resource: nil,
          metadata: {
            service_name: @service_name,
            output: result[:output]
          }
        )

        ServiceResponse.success(
          data: {
            service: @service_name,
            restarted: true,
            output: result[:output]
          }
        )
      else
        ServiceResponse.failure(error: result[:error])
      end
    rescue => e
      ServiceResponse.failure(error: "Restart failed: #{e.message}")
    end

    private

    def restart_container
      # In production, this would run: docker compose restart <service>
      # For now, we'll simulate it or run it if Docker is available

      if production_environment?
        execute_docker_restart
      else
        simulate_restart
      end
    end

    def execute_docker_restart
      command = "docker compose restart #{@service_name}"
      output = `#{command} 2>&1`
      success = $?.success?

      {
        success: success,
        output: output,
        error: success ? nil : output
      }
    rescue => e
      {
        success: false,
        output: "",
        error: e.message
      }
    end

    def simulate_restart
      # Development simulation
      {
        success: true,
        output: "[DEV] Simulated restart of #{@service_name}",
        error: nil
      }
    end

    def production_environment?
      ENV["RAILS_ENV"] == "production" || ENV["DOCKER_ENV"] == "true"
    end
  end
end
