# frozen_string_literal: true

require "open3"
require "json"
require "shellwords"

module Mcp
  # One long-lived stdio MCP server process and its JSON-RPC conversation.
  # Starting it runs the initialize handshake; callers then send requests over
  # the same pipes. Not thread-safe: Mcp::StdioRegistry serializes access.
  class StdioSession
    PROTOCOL_VERSION = "2025-03-26"
    REQUEST_TIMEOUT = 60
    HANDSHAKE_TIMEOUT = 30
    STDERR_TAIL_LINES = 20

    class Error < StandardError; end

    # The server answered with a JSON-RPC error; the session itself is still healthy.
    class RpcError < Error; end

    WORKSPACE_CONTAINER = "#{ENV.fetch('COMPOSE_PROJECT_NAME', 'hivemind')}-workspace-1"

    # @return [Array<String>] argv that runs the server's command inside the workspace container
    def self.command_for(server)
      env_args = server.resolved_env_vars.flat_map { |k, v| [ "--env", "#{k}=#{v}" ] }
      [ "docker", "exec", "-i", *env_args, WORKSPACE_CONTAINER, *server.resolved_command_args ]
    end

    attr_reader :last_used_at

    # @param argv [Array<String>] the command to spawn
    def initialize(argv)
      @argv = argv
      @next_id = 0
      @buffer = +""
      @stderr_tail = []
      @last_used_at = Time.current
    end

    # Spawns the process and completes the MCP handshake.
    # @return [self]
    def start
      @stdin, @stdout, stderr, @wait_thr = Open3.popen3(*@argv)
      @stderr_thread = Thread.new { drain(stderr) }
      request("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "hivemind", version: "1.0" }
      }, timeout: HANDSHAKE_TIMEOUT)
      write_message(jsonrpc: "2.0", method: "notifications/initialized")
      self
    rescue StandardError
      close
      raise
    end

    # @return [Integer, nil] the spawned process id
    def pid
      @wait_thr&.pid
    end

    def alive?
      !@wait_thr.nil? && @wait_thr.alive?
    end

    # Sends one request and waits for its response.
    # @return [Hash] the response's +result+
    # @raise [Error] on a JSON-RPC error, timeout, or the process exiting
    def request(method, params, timeout: REQUEST_TIMEOUT)
      @next_id += 1
      id = @next_id
      write_message(jsonrpc: "2.0", id: id, method: method, params: params)
      message = read_response(id, timeout)
      @last_used_at = Time.current
      raise RpcError, "#{message['error']['message']} (code #{message['error']['code']})" if message["error"]

      message["result"] || {}
    end

    # Stops the process: closes stdin, then terminates it if it lingers.
    def close
      @stdin.close unless @stdin.nil? || @stdin.closed?
      @wait_thr.join(2) || terminate if @wait_thr
      @stdout.close unless @stdout.nil? || @stdout.closed?
      @stderr_thread&.kill
    rescue IOError, SystemCallError
      nil
    end

    private

    def terminate
      Process.kill("TERM", @wait_thr.pid)
      @wait_thr.join(2) || Process.kill("KILL", @wait_thr.pid)
    rescue Errno::ESRCH
      nil
    end

    def write_message(payload)
      @stdin.write("#{payload.to_json}\n")
      @stdin.flush
    rescue IOError, SystemCallError => e
      raise Error, "MCP server process is not running (#{e.message})#{stderr_hint}"
    end

    def read_response(id, timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        while (line = next_line)
          message = parse(line)
          return message if message.is_a?(Hash) && message["id"] == id && (message.key?("result") || message.key?("error"))
        end
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Error, "MCP server did not respond within #{timeout}s#{stderr_hint}" if remaining <= 0
        raise Error, "MCP server closed its output#{stderr_hint}" unless fill_buffer(remaining)
      end
    end

    def next_line
      index = @buffer.index("\n")
      return unless index

      @buffer.slice!(0..index).strip
    end

    # @return [Boolean] false at end of stream
    def fill_buffer(wait)
      return true unless @stdout.wait_readable(wait)

      @buffer << @stdout.read_nonblock(65_536)
      true
    rescue EOFError
      false
    rescue IO::WaitReadable
      true
    end

    def parse(line)
      return nil if line.empty?

      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    def drain(stream)
      stream.each_line do |line|
        @stderr_tail << line.strip
        @stderr_tail.shift while @stderr_tail.size > STDERR_TAIL_LINES
      end
    rescue IOError
      nil
    end

    def stderr_hint
      tail = @stderr_tail.last(3).reject(&:empty?).join(" | ")
      tail.empty? ? "" : ": #{tail}"
    end
  end
end
