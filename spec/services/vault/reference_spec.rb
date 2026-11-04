# frozen_string_literal: true

require "rails_helper"

RSpec.describe Vault::Reference do
  it "recognises vault:namespace/key" do
    expect(described_class.valid?("vault:stripe/api_key")).to be(true)
    expect(described_class.parse("vault:stripe/api_key")).to eq(namespace: "stripe", key: "api_key")
  end

  it "rejects raw secrets and malformed references" do
    [ "sk-live-123", "vault:", "vault:ns", "vault:ns/", "vault:a/b/c", "VAULT:a/b", nil, 5 ].each do |value|
      expect(described_class.valid?(value)).to be(false), value.inspect
    end
  end

  it "resolves to the stored value" do
    create(:vault_entry, namespace: "stripe", key: "api_key", value: "sk-test-1234")

    result = described_class.resolve("vault:stripe/api_key")

    expect(result).to be_success
    expect(result.data[:value]).to eq("sk-test-1234")
  end

  it "fails for a missing entry or a non-reference" do
    expect(described_class.resolve("vault:stripe/none")).not_to be_success
    expect(described_class.resolve("sk-test-1234")).not_to be_success
  end
end
