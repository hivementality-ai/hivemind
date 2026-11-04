# frozen_string_literal: true

module Mcp
  # Keeps one running stdio session per MCP server for the life of this
  # process, so tool calls reuse it instead of spawning a server each time.
  # A session that died or whose server config changed is replaced, one idle
  # past IDLE_TIMEOUT is shut down, and all are closed at exit.
  class StdioRegistry
    IDLE_TIMEOUT = 300
    REAP_INTERVAL = 30

    INSTANCE_LOCK = Mutex.new
    Slot = Struct.new(:mutex, :session, :fingerprint)

    def self.instance
      INSTANCE_LOCK.synchronize { @instance ||= new.tap { |registry| at_exit { registry.shutdown } } }
    end

    class << self
      delegate :with_session, :close, :reap_idle, :shutdown, to: :instance
    end

    def initialize(idle_timeout: IDLE_TIMEOUT)
      @idle_timeout = idle_timeout
      @mutex = Mutex.new
      @slots = {}
    end

    # Yields a live session for the server, starting or replacing one as needed.
    # Calls to the same server are serialized. A failure inside the block
    # discards the session so the next call starts fresh, except a JSON-RPC
    # error reply, which leaves a healthy session in place.
    def with_session(server)
      slot = @mutex.synchronize { @slots[server.id] ||= Slot.new(Mutex.new) }
      ensure_reaper
      slot.mutex.synchronize do
        refresh(slot, server)
        begin
          yield slot.session
        rescue StandardError => e
          discard(slot) unless e.is_a?(StdioSession::RpcError)
          raise
        end
      end
    end

    # Shuts down the server's session, if any.
    def close(server)
      slot = @mutex.synchronize { @slots[server.id] }
      slot&.mutex&.synchronize { discard(slot) }
    end

    # Shuts down sessions idle longer than the idle timeout.
    def reap_idle
      slots = @mutex.synchronize { @slots.values }
      slots.each do |slot|
        next unless slot.mutex.try_lock

        begin
          session = slot.session
          discard(slot) if session && (!session.alive? || Time.current - session.last_used_at > @idle_timeout)
        ensure
          slot.mutex.unlock
        end
      end
    end

    def shutdown
      @reaper&.kill
      slots = @mutex.synchronize { @slots.values }
      slots.each { |slot| discard(slot) }
    end

    private

    def refresh(slot, server)
      fingerprint = [ server.command, server.resolved_env_vars ].hash
      return if slot.session&.alive? && slot.fingerprint == fingerprint

      discard(slot)
      slot.session = StdioSession.new(StdioSession.command_for(server)).start
      slot.fingerprint = fingerprint
    end

    def discard(slot)
      slot.session&.close
      slot.session = nil
    end

    def ensure_reaper
      return if @reaper&.alive?

      @mutex.synchronize do
        @reaper = Thread.new { reap_loop } unless @reaper&.alive?
      end
    end

    def reap_loop
      loop do
        sleep REAP_INTERVAL
        reap_idle
      end
    end
  end
end
