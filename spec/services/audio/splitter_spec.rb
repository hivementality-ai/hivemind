# frozen_string_literal: true

require "rails_helper"

RSpec.describe Audio::Splitter do
  let(:audio) do
    Tempfile.new([ "clip", ".mp3" ]).tap do |file|
      file.write("x" * 100)
      file.close
    end
  end
  let(:ok) { instance_double(Process::Status, success?: true) }

  it "yields a small file untouched without calling ffmpeg" do
    expect(Open3).not_to receive(:capture3)

    pieces = []
    described_class.each_piece(audio.path, limit: 1000) { |piece| pieces << piece }

    expect(pieces).to eq([ audio.path ])
  end

  it "cuts a big file by time from its bitrate and yields the pieces in order" do
    segment_time = nil
    allow(Open3).to receive(:capture3) do |*cmd|
      if cmd.first == "ffprobe"
        [ "10.0\n", "", ok ]
      else
        segment_time = cmd[cmd.index("-segment_time") + 1]
        %w[0002 0000 0001].each { |n| File.write(File.join(File.dirname(cmd.last), "piece-#{n}.mp3"), "p#{n}") }
        [ "", "", ok ]
      end
    end

    names = []
    described_class.each_piece(audio.path, limit: 50) { |piece| names << File.basename(piece) }

    expect(names).to eq(%w[piece-0000.mp3 piece-0001.mp3 piece-0002.mp3])
    expect(segment_time).to eq("10")
  end

  it "says so plainly when ffmpeg is missing" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

    expect { described_class.each_piece(audio.path, limit: 50) { nil } }
      .to raise_error(described_class::Failure, /ffmpeg is not installed/)
  end
end
