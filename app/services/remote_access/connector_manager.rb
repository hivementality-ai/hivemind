# frozen_string_literal: true

require "open3"

module RemoteAccess
  # Starts/stops/restarts the managed `cloudflared` sidecar (docker-compose.yml,
  # profile "tunnel") via the same docker-proxy Docker API access the rest of
  # the app uses for host-repo compose commands
  # (see Tools::PlatformControlExecutor) — `docker compose` shells out over
  # DOCKER_HOST=tcp://docker-proxy:2375 against the host-mounted compose file
  # at HOST_DIR, so no direct socket or extra client library is needed here.
  class ConnectorManager
    HOST_DIR = "/host-hivemind"
    SERVICE = "cloudflared"
    PROFILE = "tunnel"

    def self.start
      new.start
    end

    def self.stop
      new.stop
    end

    def self.restart
      new.restart
    end

    def self.status
      new.status
    end

    def start
      run("up", "-d", SERVICE)
    end

    # Brings up compose services, enabling the given profiles on top of the
    # ones already configured.
    def up(services, profiles:)
      run("up", "-d", *services, profiles: profiles)
    end

    def stop
      run("stop", SERVICE)
    end

    def restart
      run("restart", SERVICE)
    end

    # Returns :running, :stopped, or :unknown (e.g. host dir not mounted,
    # container never created).
    def status
      unless File.directory?(HOST_DIR)
        return ServiceResponse.failure(error: "Host directory not mounted at #{HOST_DIR}", payload: { state: :unknown })
      end

      output, _stderr, process_status = run_compose("ps", "--format", "{{.State}}", SERVICE)
      return ServiceResponse.failure(error: output, payload: { state: :unknown }) unless process_status&.success?

      state = output.to_s.strip.downcase
      normalized = state.include?("running") ? :running : (state.empty? ? :stopped : :unknown)
      ServiceResponse.success(data: { state: normalized, raw: state })
    end

    private

    def run(*args, profiles: [])
      unless File.directory?(HOST_DIR)
        return ServiceResponse.failure(error: "Host directory not mounted at #{HOST_DIR}. Ensure the volume mount exists in docker-compose.yml.")
      end

      output, _stderr, process_status = run_compose(*args, profiles: profiles)
      if process_status&.success?
        ServiceResponse.success(data: { output: output.to_s })
      else
        ServiceResponse.failure(error: output.to_s.presence || "docker compose #{args.join(' ')} failed")
      end
    end

    def run_compose(*args, profiles: [])
      composed = Channels::ComposeProfiles.merge(ENV["COMPOSE_PROFILES"], PROFILE, profiles.join(","))
      full_env = ENV.to_h.merge("COMPOSE_PROFILES" => composed)
      cmd = [ "docker", "compose", *args ]
      Open3.capture3(full_env, *cmd, chdir: HOST_DIR)
    rescue StandardError => e
      [ "Error: #{e.message}", "", nil ]
    end
  end
end
