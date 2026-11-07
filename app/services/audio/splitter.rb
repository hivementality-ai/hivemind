# frozen_string_literal: true

require "open3"
require "tmpdir"

module Audio
  # Cuts a recording into pieces under a size limit, in order, using ffmpeg.
  class Splitter
    Failure = Class.new(StandardError)
    DEFAULT_LIMIT_MB = 24
    MIN_PIECE_SECONDS = 10

    # @return [Integer] largest piece sent to the speech service, in bytes
    def self.limit_bytes
      Integer(ENV.fetch("HIVEMIND_TRANSCRIBE_CHUNK_MB", DEFAULT_LIMIT_MB)).megabytes
    end

    # Yields each piece (the file itself when it already fits) in order.
    #
    # @param path [String]
    # @param limit [Integer] bytes
    # @yieldparam piece_path [String]
    # @raise [Failure] when the file is too big and cannot be cut
    def self.each_piece(path, limit: limit_bytes, &block)
      return yield(path) if File.size(path) <= limit

      new(path, limit).each_piece(&block)
    end

    def initialize(path, limit)
      @path = path
      @limit = limit
    end

    # @yieldparam piece_path [String]
    def each_piece(&)
      Dir.mktmpdir("audio-split") do |dir|
        run("ffmpeg", "-v", "error", "-i", @path, "-f", "segment", "-segment_time", seconds_per_piece.to_s,
            "-c", "copy", "-reset_timestamps", "1", File.join(dir, "piece-%04d#{File.extname(@path)}"))
        pieces = Dir[File.join(dir, "piece-*")].sort
        raise Failure, "The recording could not be split into smaller parts." if pieces.empty?

        pieces.each(&)
      end
    end

    private

    def seconds_per_piece
      bytes_per_second = File.size(@path) / duration
      [ (@limit * 0.9 / bytes_per_second).floor, MIN_PIECE_SECONDS ].max
    end

    def duration
      seconds = Float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", @path).strip,
                      exception: false)
      raise Failure, "Could not read how long the recording is." unless seconds&.positive?

      seconds
    end

    def run(*cmd)
      out, err, status = Open3.capture3(*cmd)
      unless status.success?
        raise Failure, "The recording is too large to send in one piece and splitting it failed: #{err.to_s.strip.truncate(80)}"
      end

      out
    rescue Errno::ENOENT
      raise Failure, "This recording is too large for the speech service and ffmpeg is not installed to split it. Try a shorter clip."
    end
  end
end
