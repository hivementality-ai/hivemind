# frozen_string_literal: true

require "digest"

module Tools
  # Session-scoped cache for file-read tool results. On re-read of the same
  # path within a single session, the agent gets a short "unchanged since
  # turn N" marker with the content hash instead of the full file content.
  # The original read is still in the conversation history, so the LLM can
  # scroll back if it needs the bytes — but the re-read turn costs <50
  # tokens instead of the full file.
  #
  # Invalidation is manual: the executor calls `on_write(path)` for any
  # file_write or file_edit tool run in the same session.
  #
  # Ported from rubyn-code's Tools::FileCache, adapted to hivemind's
  # multi-process Rails app via Rails.cache.
  class FileCache
    NAMESPACE = "tool_file_cache"
    TTL = 1.hour

    class << self
      def for(session)
        new(session_id: session&.id)
      end

      # Intercept a read-like tool call. Returns a ServiceResponse-shaped
      # hash if there's a cache hit, or nil if the caller should execute
      # normally.
      def try_read_hit(session:, path:)
        cache_for(session).try_read_hit(path)
      end

      def record_read(session:, path:, content:)
        cache_for(session).record_read(path, content)
      end

      def invalidate(session:, path:)
        cache_for(session).invalidate(path)
      end

      private

      def cache_for(session)
        new(session_id: session&.id)
      end
    end

    def initialize(session_id:)
      @session_id = session_id
    end

    def try_read_hit(path)
      return nil unless @session_id
      return nil if path.to_s.strip.empty?

      entry = Rails.cache.read(key_for(path))
      return nil unless entry

      short_output = "[cached] File unchanged since earlier in this session (sha256: #{entry[:hash][0, 12]}). " \
                     "See prior tool_result for content."
      { output: short_output, hit: true, hash: entry[:hash] }
    rescue StandardError => e
      Rails.logger.warn("[Tools::FileCache] try_read_hit failed: #{e.message}") if defined?(Rails)
      nil
    end

    def record_read(path, content)
      return unless @session_id
      return if path.to_s.strip.empty?

      hash = Digest::SHA256.hexdigest(content.to_s)
      Rails.cache.write(key_for(path), { hash: hash, recorded_at: Time.current.to_i }, expires_in: TTL)
      hash
    rescue StandardError => e
      Rails.logger.warn("[Tools::FileCache] record_read failed: #{e.message}") if defined?(Rails)
      nil
    end

    def invalidate(path)
      return unless @session_id
      return if path.to_s.strip.empty?
      Rails.cache.delete(key_for(path))
    rescue StandardError => e
      Rails.logger.warn("[Tools::FileCache] invalidate failed: #{e.message}") if defined?(Rails)
      nil
    end

    private

    def key_for(path)
      digest = Digest::SHA256.hexdigest(path.to_s)
      "#{NAMESPACE}:#{@session_id}:#{digest}"
    end
  end
end
