# frozen_string_literal: true

require "open3"

module Mcp
  class ProcessManager
    WORKSPACE_CONTAINER = "hivemind-workspace-1"

    def initialize(server)
      @server = server
    end

    def start
      install_package if @server.npm_package.present?
      spawn_process
    rescue StandardError => e
      @server.mark_error!(e.message)
      ServiceResponse.failure(error: e.message)
    end

    def stop
      pid = @server.metadata&.dig("pid")
      kill_process(pid) if pid
      @server.mark_disconnected!
      ServiceResponse.success(data: { stopped: true })
    rescue StandardError => e
      @server.mark_disconnected!
      ServiceResponse.success(data: { stopped: true, warning: e.message })
    end

    private

    def install_package
      _, stderr, status = Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER,
        "npm", "install", "-g", @server.npm_package
      )
      raise "npm install failed: #{stderr}" unless status.success?
    end

    def spawn_process
      env_args = build_env_args
      cmd = [ "docker", "exec", "-d", *env_args, WORKSPACE_CONTAINER, "sh", "-c", "#{@server.command} & echo $!" ]
      stdout, stderr, status = Open3.capture3(*cmd)
      raise "Failed to start: #{stderr}" unless status.success?

      pid = stdout.strip.split("\n").last&.strip
      tools_result = Mcp::StdioClient.discover_tools(@server)
      tools = tools_result.success? ? tools_result.data[:tools] : []
      @server.mark_connected!(pid: pid, tools: tools)
      ServiceResponse.success(data: { pid: pid, tools: tools })
    end

    def kill_process(pid)
      Open3.capture3("docker", "exec", WORKSPACE_CONTAINER, "kill", pid.to_s)
    end

    def build_env_args
      @server.resolved_env_vars.flat_map { |k, v| [ "--env", "#{k}=#{v}" ] }
    end
  end
end
