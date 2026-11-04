require "rails_helper"
require "yaml"

RSpec.describe "docker-compose.yml" do
  let(:services) { YAML.load_file(Rails.root.join("docker-compose.yml")).fetch("services") }

  %w[app worker-system worker-agents].each do |name|
    describe name do
      it "defines a healthcheck" do
        expect(services.dig(name, "healthcheck", "test")).to be_present
      end

      it "allows longer than Sidekiq's 25s shutdown timeout before SIGKILL" do
        expect(services.dig(name, "stop_grace_period")).to eq("30s")
      end
    end
  end

  it "probes Rails' /up route on the app" do
    expect(services.dig("app", "healthcheck", "test").join(" ")).to include("localhost:3000/up")
  end

  it "probes for a live sidekiq process on both workers" do
    %w[worker-system worker-agents].each do |name|
      expect(services.dig(name, "healthcheck", "test").join(" ")).to include("[s]idekiq")
    end
  end

  it "holds the workers until the app is healthy" do
    %w[worker-system worker-agents].each do |name|
      expect(services.dig(name, "depends_on", "app", "condition")).to eq("service_healthy")
    end
  end
end
