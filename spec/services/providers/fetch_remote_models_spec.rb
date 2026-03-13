# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::FetchRemoteModels, type: :service do
  describe ".call" do
    context "with unknown provider" do
      it "returns failure" do
        result = described_class.call(:unknown)
        expect(result).not_to be_success
        expect(result.error).to include("Unknown provider")
      end
    end

    context "with ollama" do
      it "returns models on success" do
        stub_request(:get, "http://host.docker.internal:11434/api/tags")
          .to_return(status: 200, body: {
            models: [
              { name: "llama2", size: 3_800_000_000, details: { parameter_size: "7B", family: "llama" } },
              { name: "mistral", size: 4_100_000_000, details: { parameter_size: "7B", family: "mistral" } }
            ]
          }.to_json)

        result = described_class.call(:ollama)
        expect(result).to be_success
        expect(result.data[:models].size).to eq(2)
        expect(result.data[:models].first[:name]).to eq("llama2")
      end

      it "uses custom URL" do
        stub_request(:get, "http://custom:11434/api/tags")
          .to_return(status: 200, body: { models: [] }.to_json)

        result = described_class.call(:ollama, url: "http://custom:11434")
        expect(result).to be_success
      end

      it "returns failure on connection error" do
        stub_request(:get, "http://host.docker.internal:11434/api/tags")
          .to_raise(Errno::ECONNREFUSED)

        result = described_class.call(:ollama)
        expect(result).not_to be_success
      end
    end

    context "with llama_cpp" do
      it "returns models on success" do
        stub_request(:get, "http://host.docker.internal:8080/v1/models")
          .to_return(status: 200, body: {
            data: [ { id: "default" } ]
          }.to_json)

        result = described_class.call(:llama_cpp)
        expect(result).to be_success
        expect(result.data[:models].first[:id]).to eq("default")
      end
    end

    context "with invalid URL" do
      it "returns failure for SSRF attempt" do
        result = described_class.call(:ollama, url: "file:///etc/passwd")
        expect(result).not_to be_success
      end
    end
  end
end
