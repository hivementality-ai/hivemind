# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::HealthCheck do
  describe ".call" do
    it "returns zero counts when no connected servers" do
      result = described_class.call
      expect(result).to be_success
      expect(result.data).to eq({ checked: 0, healthy: 0, unhealthy: 0 })
    end

    context "with stdio server" do
      let!(:server) { create(:mcp_server, :stdio, :connected, metadata: { "pid" => "12345" }) }

      it "marks healthy when process is alive" do
        allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true)])
        result = described_class.call
        expect(result.data[:healthy]).to eq(1)
      end

      it "marks unhealthy when process is dead" do
        allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: false)])
        result = described_class.call
        expect(result.data[:unhealthy]).to eq(1)
      end

      it "marks unhealthy when no PID" do
        server.update!(metadata: {})
        result = described_class.call
        expect(result.data[:unhealthy]).to eq(1)
      end
    end

    context "with SSE server" do
      let!(:server) { create(:mcp_server, :sse, :connected) }

      it "marks healthy on successful HEAD" do
        stub_request(:head, "https://mcp.example.com/").to_return(status: 200)
        result = described_class.call
        expect(result.data[:healthy]).to eq(1)
      end

      it "marks unhealthy on HTTP error" do
        stub_request(:head, "https://mcp.example.com/").to_return(status: 500)
        result = described_class.call
        expect(result.data[:unhealthy]).to eq(1)
      end

      it "marks unhealthy on connection failure" do
        stub_request(:head, "https://mcp.example.com/").to_raise(Errno::ECONNREFUSED)
        result = described_class.call
        expect(result.data[:unhealthy]).to eq(1)
      end
    end

    it "skips disabled servers" do
      create(:mcp_server, :disabled, status: "connected")
      result = described_class.call
      expect(result.data[:checked]).to eq(0)
    end

    it "skips disconnected servers" do
      create(:mcp_server, :disconnected)
      result = described_class.call
      expect(result.data[:checked]).to eq(0)
    end
  end
end
