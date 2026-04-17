# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts workspace files from disk into a swarm workspace_files[] entry.
    #
    # Each entry captures:
    #   path    – relative path from the workspace root (e.g. "scripts/boot.sh")
    #   content – Base64-encoded file content (binary-safe)
    #   encoding – always "base64"
    #   size    – byte size of the raw (decoded) content
    #
    # Only files under WORKSPACE_ROOT are included. Directories and symlinks are
    # skipped. Files larger than MAX_FILE_BYTES are also skipped (a warning is
    # emitted but the export does not fail).
    #
    # Usage:
    #   result = WorkspaceFilesSerializer.call(paths: ["scripts/boot.sh", "README.md"])
    #   result.success?                    # => true / false
    #   result.payload[:workspace_files]   # => Array<Hash>
    #   result.payload[:skipped]           # => Array<String> (paths that were skipped)
    class WorkspaceFilesSerializer
      WORKSPACE_ROOT = "/workspace"
      MAX_FILE_BYTES = 1 * 1024 * 1024  # 1 MiB per file

      def self.call(paths: [])
        new(paths).call
      end

      def initialize(paths)
        @paths   = Array(paths).map(&:to_s).reject(&:blank?)
        @skipped = []
      end

      def call
        workspace_files = @paths.filter_map { |rel| serialize_file(rel) }

        ServiceResponse.success(
          payload: {
            workspace_files: workspace_files,
            skipped:         @skipped.dup
          }
        )
      rescue StandardError => e
        ServiceResponse.error(message: "WorkspaceFilesSerializer failed: #{e.message}")
      end

      private

      def serialize_file(relative_path)
        absolute = safe_absolute(relative_path)
        unless absolute
          @skipped << relative_path
          return nil
        end

        unless File.file?(absolute)
          @skipped << relative_path
          return nil
        end

        size = File.size(absolute)
        if size > MAX_FILE_BYTES
          @skipped << relative_path
          return nil
        end

        raw     = File.binread(absolute)
        encoded = Base64.strict_encode64(raw)

        {
          "path"     => relative_path,
          "content"  => encoded,
          "encoding" => "base64",
          "size"     => size
        }
      end

      # Returns the absolute path only when it safely resolves inside WORKSPACE_ROOT.
      # Returns nil for path traversal attempts or paths outside the root.
      def safe_absolute(relative_path)
        return nil if relative_path.blank?
        return nil if relative_path.include?("..")
        return nil if relative_path.start_with?("/")

        candidate = File.join(WORKSPACE_ROOT, relative_path)
        realpath  = File.realpath(candidate) rescue nil
        return nil unless realpath

        root_real = File.realpath(WORKSPACE_ROOT) rescue WORKSPACE_ROOT
        return nil unless realpath.start_with?("#{root_real}/") || realpath == root_real

        candidate
      end
    end
  end
end
