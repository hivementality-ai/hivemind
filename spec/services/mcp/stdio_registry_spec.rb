# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::StdioRegistry do
  subject(:registry) { described_class.new(idle_timeout: 300) }

  let(:server) { create(:mcp_server, :stdio, :connected) }

  before do
    allow(Mcp::StdioSession).to receive(:command_for)
      .and_return([ RbConfig.ruby, Rails.root.join("spec/fixtures/mcp/echo_server.rb").to_s ])
  end

  after { registry.shutdown }

  def pid_of(srv = server)
    registry.with_session(srv) do |session|
      session.request("tools/call", { name: "echo", arguments: {} }).dig("content", 0, "text")
    end
  end

  it "reuses the same process for a second call" do
    expect(pid_of).to eq(pid_of)
  end

  it "keeps separate processes for separate servers" do
    other = create(:mcp_server, :stdio, :connected)

    expect(pid_of(other)).not_to eq(pid_of)
  end

  it "respawns a process that died during a call" do
    first = pid_of
    expect do
      registry.with_session(server) { |s| s.request("tools/call", { name: "die", arguments: {} }) }
    end.to raise_error(Mcp::StdioSession::Error)

    expect(pid_of).not_to eq(first)
  end

  it "respawns a process killed between calls" do
    first = pid_of
    registry.with_session(server) do |s|
      Process.kill("KILL", s.pid)
      sleep 0.2
    end

    expect(pid_of).not_to eq(first)
  end

  it "keeps the same process after a JSON-RPC error response" do
    first = pid_of
    expect do
      registry.with_session(server) { |s| s.request("tools/call", { name: "fail", arguments: {} }) }
    end.to raise_error(Mcp::StdioSession::RpcError, /tool exploded/)

    expect(pid_of).to eq(first)
  end

  it "builds a single shared instance across threads" do
    described_class.instance_variable_set(:@instance, nil)
    instances = 8.times.map { Thread.new { described_class.instance } }.map(&:value)

    expect(instances.uniq.size).to eq(1)
  ensure
    described_class.shutdown
    described_class.instance_variable_set(:@instance, nil)
  end

  it "starts a fresh process when the server command changes" do
    first = pid_of
    server.update!(command: "other-command")

    expect(pid_of).not_to eq(first)
  end

  it "shuts down a session idle past the timeout" do
    short = described_class.new(idle_timeout: 0)
    session = short.with_session(server) { |s| s }
    sleep 0.05
    short.reap_idle

    expect(session).not_to be_alive
  ensure
    short&.shutdown
  end

  it "keeps a session that is still within the idle timeout" do
    session = registry.with_session(server) { |s| s }
    registry.reap_idle

    expect(session).to be_alive
  end

  it "closes a server's session on demand" do
    session = registry.with_session(server) { |s| s }
    registry.close(server)

    expect(session).not_to be_alive
  end

  it "closes every session on shutdown" do
    session = registry.with_session(server) { |s| s }
    registry.shutdown

    expect(session).not_to be_alive
  end
end
