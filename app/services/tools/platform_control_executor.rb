# frozen_string_literal: true

require "open3"

module Tools
  class PlatformControlExecutor < BaseExecutor
    # Runs on the app container which has Docker access via docker-proxy.
    # The workspace container cannot do this — it has no Docker socket.

    HIVEMIND_DIR = Rails.root.to_s
    COMPOSE_TIMEOUT = 300 # 5 minutes for pulls/restarts

    def call
      action = input["action"].to_s.strip
      return ServiceResponse.failure(error: "No action provided") if action.empty?

      case action
      when "restart"
        restart_services(input["services"])
      when "update"
        update_hivemind(rc: input["rc"] == true)
      when "status"
        platform_status
      when "version"
        current_version
      when "logs"
        fetch_logs(input["service"] || "app", input["lines"] || 50)
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Use: restart, update, status, version, logs")
      end
    end

    private

    def current_version
      version = ENV.fetch("HIVEMIND_VERSION", "dev")
      ServiceResponse.success(data: { output: "Hivemind version: #{version}" })
    end

    def platform_status
      output, _, status = run_compose("ps", "--format", "table {{.Name}}\t{{.Status}}\t{{.Ports}}")
      if status&.success?
        ServiceResponse.success(data: { output: "Container status:\n#{output}" })
      else
        ServiceResponse.failure(error: "Failed to get status: #{output}")
      end
    end

    def fetch_logs(service, lines)
      lines = [ lines.to_i, 200 ].min # Cap at 200 lines
      output, _, status = run_compose("logs", "--tail", lines.to_s, "--no-color", service)
      if status&.success?
        ServiceResponse.success(data: { output: output.to_s.truncate(30_000) })
      else
        ServiceResponse.failure(error: "Failed to fetch logs: #{output}")
      end
    end

    def restart_services(services)
      services = Array(services).map(&:to_s).reject(&:blank?)

      if services.any?
        output, _, status = run_compose("restart", *services)
        msg = "Restarted: #{services.join(', ')}"
      else
        output, _, status = run_compose("restart")
        msg = "All services restarted"
      end

      if status&.success?
        ServiceResponse.success(data: { output: msg })
      else
        ServiceResponse.failure(error: "Restart failed: #{output}")
      end
    end

    def update_hivemind(rc: false)
      steps = []

      # 1. Git fetch and checkout latest tag
      fetch_out, _ = run_cmd("git", "fetch", "origin", "--tags", "--force", chdir: HIVEMIND_DIR)
      steps << "Fetched tags"

      # Find latest tag
      tags_out, _ = run_cmd("git", "tag", "--sort=-version:refname", chdir: HIVEMIND_DIR)
      latest_tag = tags_out.to_s.lines.map(&:strip).reject(&:blank?).find do |tag|
        rc ? true : !tag.include?("-rc")
      end

      unless latest_tag
        return ServiceResponse.failure(error: "No release tags found")
      end

      current_tag = run_cmd("git", "describe", "--tags", "--exact-match", chdir: HIVEMIND_DIR).first.to_s.strip
      if current_tag == latest_tag
        steps << "Already on latest: #{latest_tag}"
      else
        run_cmd("git", "checkout", latest_tag, chdir: HIVEMIND_DIR)
        steps << "Checked out #{latest_tag}"
      end

      version = latest_tag.delete_prefix("v")

      # 2. Pull prebuilt images
      pull_out, _, pull_status = run_compose("pull", "app", "workspace", "connector", "sdk-proxy",
        env: { "HIVEMIND_VERSION" => version })
      if pull_status&.success?
        steps << "Pulled prebuilt images"
      else
        steps << "Image pull failed — will use existing images"
      end

      # 3. Run migrations
      migrate_out, _, migrate_status = run_compose("run", "--rm", "-e", "RAILS_ENV=production", "app", "bin/rails", "db:migrate",
        env: { "HIVEMIND_VERSION" => version })
      steps << (migrate_status&.success? ? "Migrations complete" : "Migration skipped")

      # 4. Recreate containers
      up_out, _, up_status = run_compose("up", "-d", "--force-recreate",
        env: { "HIVEMIND_VERSION" => version })
      steps << (up_status&.success? ? "Containers recreated" : "Restart failed")

      ServiceResponse.success(data: {
        output: "Update to #{version} complete.\n\nSteps:\n#{steps.map { |s| "  ✓ #{s}" }.join("\n")}"
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Update failed: #{e.message}\n\nCompleted steps:\n#{steps.map { |s| "  ✓ #{s}" }.join("\n")}")
    end

    def run_compose(*args, env: {})
      full_env = ENV.to_h.merge(env)
      cmd = [ "docker", "compose", *args ]
      Open3.capture3(full_env, *cmd, chdir: HIVEMIND_DIR)
    rescue StandardError => e
      [ "Error: #{e.message}", "", nil ]
    end

    def run_cmd(*cmd, chdir: nil)
      opts = chdir ? { chdir: chdir } : {}
      stdout, stderr, status = Open3.capture3(*cmd, **opts)
      [ stdout.to_s + stderr.to_s, status ]
    rescue StandardError => e
      [ "Error: #{e.message}", nil ]
    end
  end
end
