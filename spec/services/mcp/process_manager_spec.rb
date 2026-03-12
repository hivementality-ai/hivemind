# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::ProcessManager do
  let(:server) { create(:mcp_server, :stdio, npm_package: "@mcp/test-server") }
  subject(:manager) { described_class.new(server) }

  describe "#start" do
    it "installs package, spawns process, and connects" do
      status_ok = instance_double(Process::Status, success?: true)
      tools_response = ServiceResponse.success(data: { tools: [] })

      allow(Open3).to receive(:capture3).and_return([ "12345\n", "", status_ok ])
      allow(Mcp::StdioClient).to receive(:discover_tools).and_return(tools_response)

      result = manager.start
      expect(result).to be_success
      expect(server.reload.status).to eq("connected")
    end

    it "marks error on npm failure" do
      allow(Open3).to receive(:capture3).and_return([ "", "npm ERR!", instance_double(Process::Status, success?: false) ])
      result = manager.start
      expect(result).not_to be_success
      expect(server.reload.status).to eq("error")
    end
  end

  describe "#stop" do
    it "kills process when pid present" do
      server.update!(metadata: { "pid" => "12345" }, status: "connected")
      allow(Open3).to receive(:capture3).and_return([ "", "", instance_double(Process::Status, success?: true) ])
      result = manager.stop
      expect(result).to be_success
      expect(server.reload.status).to eq("disconnected")
    end

    it "disconnects even without pid" do
      server.update!(status: "connected")
      result = manager.stop
      expect(result).to be_success
      expect(server.reload.status).to eq("disconnected")
    end
  end
end
