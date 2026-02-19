# frozen_string_literal: true

require "open3"

module Tools
  # Shared helper for reading/writing files inside the workspace container.
  # Avoids cross-container uid mismatch (Rails uid=1000 vs workspace uid=1001).
  module WorkspaceIo
    WORKSPACE_CONTAINER = "hivemind-workspace-1"
    WORKSPACE_ROOT = "/workspace"

    module_function

    def read_file(path, max_bytes: nil)
      cmd = max_bytes ? "head -c #{max_bytes} #{shell_escape(path)}" : "cat #{shell_escape(path)}"
      stdout, stderr, status = Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER, "bash", "-c", cmd
      )
      raise "File not found: #{path}" unless status.success?
      stdout
    end

    def write_file(path, content)
      dir = File.dirname(path)
      Open3.capture3("docker", "exec", WORKSPACE_CONTAINER, "mkdir", "-p", dir)

      IO.popen(
        [ "docker", "exec", "-i", WORKSPACE_CONTAINER, "bash", "-c", "cat > #{shell_escape(path)}" ],
        "w"
      ) { |io| io.write(content) }
    end

    def file_exists?(path)
      _, _, status = Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER, "test", "-e", path
      )
      status.success?
    end

    def directory?(path)
      _, _, status = Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER, "test", "-d", path
      )
      status.success?
    end

    def mkdir_p(path)
      Open3.capture3("docker", "exec", WORKSPACE_CONTAINER, "mkdir", "-p", path)
    end

    def shell_escape(str)
      "'" + str.gsub("'", "'\\''") + "'"
    end
  end
end
