# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connectors::AddressGuard do
  describe ".blocked_host?" do
    it "blocks cloud metadata addresses and names" do
      %w[169.254.169.254 169.254.170.2 fd00:ec2::254 100.100.100.200 168.63.129.16 metadata.google.internal
         ::ffff:169.254.169.254 fe80::1].each do |host|
        expect(described_class.blocked_host?(host)).to be(true), host
      end
    end

    it "allows ordinary public and LAN hosts" do
      %w[api.example.com 93.184.216.34 192.168.1.10 127.0.0.1 localhost].each do |host|
        expect(described_class.blocked_host?(host)).to be(false), host
      end
    end
  end

  describe ".resolve!" do
    it "rejects a name that resolves to a metadata address" do
      allow(described_class).to receive(:lookup).with("sneaky.test").and_return([ "93.184.216.34", "169.254.169.254" ])
      expect { described_class.resolve!("sneaky.test") }.to raise_error(described_class::Blocked, /blocked address/)
    end

    it "rejects a name that does not resolve" do
      allow(described_class).to receive(:lookup).and_return([])
      expect { described_class.resolve!("nowhere.test") }.to raise_error(described_class::Blocked)
    end

    it "returns the addresses of an allowed host" do
      allow(described_class).to receive(:lookup).and_return([ "93.184.216.34" ])
      expect(described_class.resolve!("api.example.com")).to eq([ "93.184.216.34" ])
    end
  end
end
