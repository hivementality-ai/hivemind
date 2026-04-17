# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::MicroCompact do
  let(:long_output) { "x" * 300 }

  let(:messages) do
    [
      { role: "user", content: "first" },
      { role: "assistant", content: "ok" },
      { role: "tool", tool_use_id: "t1", tool_name: "file_read", content: long_output },
      { role: "tool", tool_use_id: "t2", tool_name: "shell",     content: long_output },
      { role: "tool", tool_use_id: "t3", tool_name: "grep",      content: long_output },
      { role: "assistant", content: "answer" }
    ]
  end

  it "replaces old tool outputs with placeholders, keeping the most recent ones" do
    compacted = described_class.call(messages, keep_recent: 2)

    expect(compacted).to eq(1)
    expect(messages[2][:content]).to eq("[Previous: used file_read]")
    expect(messages[3][:content]).to eq(long_output)
    expect(messages[4][:content]).to eq(long_output)
  end

  it "returns 0 and doesn't mutate when tool-message count is under keep_recent" do
    small = messages.first(4)
    compacted = described_class.call(small, keep_recent: 2)
    expect(compacted).to eq(0)
  end

  it "skips messages under the min-content length" do
    messages[2][:content] = "tiny"
    compacted = described_class.call(messages, keep_recent: 2)
    expect(compacted).to eq(0)
    expect(messages[2][:content]).to eq("tiny")
  end

  it "respects preserve_tools" do
    compacted = described_class.call(messages, keep_recent: 2, preserve_tools: [ "file_read" ])
    expect(compacted).to eq(0)
    expect(messages[2][:content]).to eq(long_output)
  end

  it "does not re-compact already-compacted messages" do
    described_class.call(messages, keep_recent: 2)
    second = described_class.call(messages, keep_recent: 2)
    expect(second).to eq(0)
  end
end
