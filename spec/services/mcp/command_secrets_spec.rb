# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::CommandSecrets do
  def extract(command) = described_class.extract(command, namespace: "mcp_x")

  describe ".extract" do
    it "vaults the value after a secret-looking flag" do
      result = extract("npx some-server --api-key sk-abc123")

      expect(result.command).to eq("npx some-server --api-key vault:mcp_x/arg_api_key")
      expect(result.writes).to eq([ [ "mcp_x", "arg_api_key", "sk-abc123" ] ])
    end

    it "vaults the value joined to a flag with =" do
      result = extract("srv --token=abc123")

      expect(result.command).to eq("srv --token=vault:mcp_x/arg_token")
      expect(result.writes).to eq([ [ "mcp_x", "arg_token", "abc123" ] ])
    end

    %w[--token --api-key --apikey --key --secret --password --auth --auth-token --access_token].each do |flag|
      it "treats #{flag} as a secret flag" do
        expect(extract("srv #{flag} hunter2").writes.map(&:last)).to eq([ "hunter2" ])
      end
    end

    %w[sk-abc ghp_abc github_pat_abc xoxb-1 xoxp-1 xoxa-1 lin_api_abc secret_abc ntn_abc].each do |value|
      it "vaults a bare #{value[0, 6]} value" do
        result = extract("srv #{value}")

        expect(result.command).to eq("srv vault:mcp_x/arg_1")
        expect(result.writes).to eq([ [ "mcp_x", "arg_1", value ] ])
      end
    end

    it "keeps colliding keys apart" do
      keys = extract("srv --token a --token b").writes.map { |w| w[1] }

      expect(keys.uniq.size).to eq(2)
    end

    it "round-trips values with spaces" do
      result = extract("srv --password 'two words'")

      expect(Shellwords.shellsplit(result.command)).to eq([ "srv", "--password", "vault:mcp_x/arg_password" ])
      expect(result.writes.first.last).to eq("two words")
    end

    it "leaves ordinary arguments alone" do
      command = "npx -y @modelcontextprotocol/server-filesystem /workspace --port 3000 --config ./app.json --verbose"
      result = extract(command)

      expect(result.command).to eq(command)
      expect(result.writes).to be_empty
    end

    it "does not vault a file path given to a key flag" do
      expect(extract("srv --key /home/me/key.pem --secret ./s.txt").writes).to be_empty
    end

    it "does not vault flags that merely contain a secret word" do
      expect(extract("srv --keyfile x --token-limit 5 --monkey 3").writes).to be_empty
    end

    it "does not take a following flag as a value" do
      expect(extract("srv --token --verbose").writes).to be_empty
    end

    it "does not vault the executable itself" do
      expect(extract("sk-tool run").writes).to be_empty
    end

    it "skips arguments that are already references" do
      command = "srv --api-key vault:mcp_x/arg_api_key --token=vault:mcp_x/arg_token"

      expect(extract(command)).to have_attributes(command: command, writes: [])
    end

    it "returns an unparseable command untouched" do
      expect(extract("srv --token 'unclosed")).to have_attributes(command: "srv --token 'unclosed", writes: [])
    end
  end

  describe ".resolve" do
    it "swaps whole-argument and flag= references for the vaulted value" do
      VaultEntry.create!(namespace: "mcp_x", key: "arg_api_key", value: "sk-real")
      VaultEntry.create!(namespace: "mcp_x", key: "arg_token", value: "tok-real")

      args = described_class.resolve("srv --api-key vault:mcp_x/arg_api_key --token=vault:mcp_x/arg_token --port 3000")

      expect(args).to eq([ "srv", "--api-key", "sk-real", "--token=tok-real", "--port", "3000" ])
    end

    it "leaves a reference with no vault entry as written" do
      expect(described_class.resolve("srv vault:mcp_x/missing")).to eq([ "srv", "vault:mcp_x/missing" ])
    end
  end
end
