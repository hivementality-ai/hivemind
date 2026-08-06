# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteAccess::ConnectorManager, type: :service do
  subject(:manager) { described_class.new }

  before do
    allow(File).to receive(:directory?).and_call_original
    allow(File).to receive(:directory?).with(described_class::HOST_DIR).and_return(true)
  end

  describe "#start" do
    it "runs docker compose up -d for the cloudflared service" do
      expect(Open3).to receive(:capture3).with(
        hash_including("COMPOSE_PROFILES" => "tunnel"),
        "docker", "compose", "up", "-d", "cloudflared",
        chdir: described_class::HOST_DIR
      ).and_return([ "started", "", instance_double(Process::Status, success?: true) ])

      result = manager.start
      expect(result).to be_success
    end
  end

  describe "#stop" do
    it "runs docker compose stop for the cloudflared service" do
      expect(Open3).to receive(:capture3).with(
        anything, "docker", "compose", "stop", "cloudflared", chdir: described_class::HOST_DIR
      ).and_return([ "stopped", "", instance_double(Process::Status, success?: true) ])

      result = manager.stop
      expect(result).to be_success
    end
  end

  describe "#restart" do
    it "runs docker compose restart for the cloudflared service" do
      expect(Open3).to receive(:capture3).with(
        anything, "docker", "compose", "restart", "cloudflared", chdir: described_class::HOST_DIR
      ).and_return([ "restarted", "", instance_double(Process::Status, success?: true) ])

      result = manager.restart
      expect(result).to be_success
    end
  end

  describe "#status" do
    it "reports running when the container state includes 'running'" do
      allow(Open3).to receive(:capture3)
        .and_return([ "running", "", instance_double(Process::Status, success?: true) ])

      result = manager.status
      expect(result).to be_success
      expect(result.data[:state]).to eq(:running)
    end

    it "reports stopped when there is no output" do
      allow(Open3).to receive(:capture3)
        .and_return([ "", "", instance_double(Process::Status, success?: true) ])

      result = manager.status
      expect(result.data[:state]).to eq(:stopped)
    end

    it "fails when the host directory is not mounted" do
      allow(File).to receive(:directory?).with(described_class::HOST_DIR).and_return(false)

      result = manager.status
      expect(result).not_to be_success
    end

    it "fails when docker compose errors out" do
      allow(Open3).to receive(:capture3)
        .and_return([ "some docker error", "", instance_double(Process::Status, success?: false) ])

      result = manager.status
      expect(result).not_to be_success
    end
  end
end
