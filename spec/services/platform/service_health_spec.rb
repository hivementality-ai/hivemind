# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::ServiceHealth, type: :service do
  describe ".call" do
    it "returns a successful response" do
      result = described_class.call
      expect(result).to be_success
    end

    it "includes service statuses" do
      result = described_class.call
      services = result.data[:services]

      expect(services).to be_an(Array)
      expect(services.map { |s| s[:name] }).to include("Web Server", "Database", "Cache")
    end

    it "includes provider statuses" do
      create(:provider_config, :anthropic)
      result = described_class.call
      expect(result.data[:providers]).to be_an(Array)
    end

    it "includes connectivity flags" do
      result = described_class.call
      expect(result.data).to have_key(:db_connected)
      expect(result.data).to have_key(:redis_connected)
    end
  end
end
