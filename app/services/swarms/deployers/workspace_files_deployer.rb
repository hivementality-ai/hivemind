# frozen_string_literal: true

module Swarms
  module Deployers
    # Writes workspace files from a SwarmDocument's workspace_files[] section to disk.
    #
    # Each entry must have:
    #   path     – relative path (no ".." components, no leading "/")
    #   content  – file content string
    #   encoding – "base64" (default) or "plain"
    #
    # Files are written to WORKSPACE_ROOT. Parent directories are created as needed.
    # Existing files are overwritten (import is authoritative for swarm-provided files).
    #
    # Path traversal attempts are rejected and reported as errors without halting
    # the rest of the deploy — all safe files are still written.
    #
    # Payload:
    #   result.payload[:workspace_files] – Array<DeployResult>
    #
    # Usage:
    #   result = WorkspaceFilesDeployer.call(document: swarm_doc)
    #   result.success?
    #   result.payload[:workspace_files]  # => [DeployResult, ...]
    class WorkspaceFilesDeployer
      WORKSPACE_ROOT = "/workspace"

      DeployResult = Data.define(:path, :action) do
        # action – :written | :skipped
      end

      def self.call(document:)
        new(document).call
      end

      def initialize(document)
        @document = document
      end

      def call
        results = Array(@document.workspace_files).map do |entry|
          deploy_file(entry.with_indifferent_access)
        end

        ServiceResponse.success(payload: { workspace_files: results })
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy workspace files: #{e.message}")
      end

      private

      def deploy_file(entry)
        relative = entry[:path].to_s

        absolute = safe_absolute(relative)
        unless absolute
          Rails.logger.warn("[WorkspaceFilesDeployer] Skipped unsafe path: #{relative.inspect}")
          return DeployResult.new(path: relative, action: :skipped)
        end

        raw = decode_content(entry)
        FileUtils.mkdir_p(File.dirname(absolute))
        File.binwrite(absolute, raw)

        DeployResult.new(path: relative, action: :written)
      end

      def decode_content(entry)
        content  = entry[:content].to_s
        encoding = entry[:encoding].to_s.downcase

        case encoding
        when "base64"
          Base64.decode64(content)
        else
          # "plain" or unspecified — write as UTF-8 text
          content.encode("UTF-8", invalid: :replace, undef: :replace)
        end
      end

      # Returns the absolute path only when it safely resolves inside WORKSPACE_ROOT.
      # Resolves symlinks so that symlink-indirection path traversal is blocked.
      # When the target file does not yet exist, resolves the nearest existing
      # ancestor — new files can't be realpath'd before they're written.
      def safe_absolute(relative_path)
        return nil if relative_path.blank?
        return nil if relative_path.include?("..")
        return nil if relative_path.start_with?("/")

        candidate = File.join(WORKSPACE_ROOT, relative_path)
        root_real = File.realpath(WORKSPACE_ROOT) rescue WORKSPACE_ROOT

        # Resolve the nearest existing ancestor to catch symlink traversal even
        # when the leaf file doesn't exist yet.
        resolved = File.realpath(candidate) rescue File.realpath(File.dirname(candidate)) rescue nil
        return nil unless resolved
        return nil unless resolved.start_with?("#{root_real}/") || resolved == root_real

        candidate
      end
    end
  end
end
