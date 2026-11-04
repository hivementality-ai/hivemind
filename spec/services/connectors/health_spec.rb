# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connectors::Health do
  let(:connector) { create(:connector) }
  let(:url) { "https://api.widgets.test/v1/widgets/9" }

  before { allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "93.184.216.34" ]) }

  def call_get
    Connectors::Executor.call(connector: connector, operation: "get_widget", params: { "id" => "9" })
  end

  describe ".classify" do
    it "treats 404 and 405 as definition-shaped" do
      expect(described_class.classify(404)).to eq(:definition)
      expect(described_class.classify(405)).to eq(:definition)
    end

    it "treats 400 and 422 as definition-shaped only with a schema-ish body" do
      expect(described_class.classify(422, '{"error":"missing required field name"}')).to eq(:definition)
      expect(described_class.classify(400, "Bad things happened")).to eq(:other)
    end

    it "treats timeouts, 5xx and 429 as transient" do
      expect(described_class.classify(nil)).to eq(:transient)
      expect(described_class.classify(500)).to eq(:transient)
      expect(described_class.classify(503)).to eq(:transient)
      expect(described_class.classify(429)).to eq(:transient)
    end

    it "ignores auth failures" do
      expect(described_class.classify(401)).to eq(:other)
      expect(described_class.classify(403)).to eq(:other)
    end
  end

  context "when calls fail" do
    it "never hints after any number of transient failures" do
      stub_request(:get, url).to_return(status: 503, body: "down")
      results = Array.new(5) { call_get }

      expect(results.map(&:error)).to all(satisfy { |e| !e.include?("propose_connector_fix") })
      expect(connector.reload.health["get_widget"]["consecutive_failures"]).to eq(0)
    end

    it "never hints after repeated timeouts or 429s" do
      stub_request(:get, url).to_timeout
      4.times { call_get }
      stub_request(:get, url).to_return(status: 429, body: "slow down")
      results = Array.new(4) { call_get }

      expect(results.map(&:error).join).not_to include("propose_connector_fix")
      expect(connector.reload.health["get_widget"]["consecutive_failures"]).to eq(0)
    end

    it "hints on the third consecutive definition failure, not before" do
      stub_request(:get, url).to_return(status: 404, body: "no route")
      errors = Array.new(3) { call_get.error }

      expect(errors[0..1].join).not_to include("propose_connector_fix")
      expect(errors[2]).to include("This connector may be out of date. You can propose a fix with propose_connector_fix.")
    end

    it "records the count, status, class and time" do
      stub_request(:get, url).to_return(status: 405, body: "nope")
      2.times { call_get }

      entry = connector.reload.health["get_widget"]
      expect(entry).to include("consecutive_failures" => 2, "last_error_class" => "definition", "last_status" => 405)
      expect(entry["last_failure_at"]).to be_present
    end

    it "does not let a transient failure reset or advance the count" do
      stub_request(:get, url).to_return(status: 404, body: "x")
      2.times { call_get }
      stub_request(:get, url).to_return(status: 500, body: "x")
      call_get

      expect(connector.reload.health["get_widget"]["consecutive_failures"]).to eq(2)
    end

    it "resets the count on success" do
      stub_request(:get, url).to_return(status: 404, body: "x")
      2.times { call_get }
      stub_request(:get, url).to_return(status: 200, body: "{}")
      call_get
      stub_request(:get, url).to_return(status: 404, body: "x")

      expect(call_get.error).not_to include("propose_connector_fix")
      expect(connector.reload.health["get_widget"]["consecutive_failures"]).to eq(1)
    end

    it "tracks operations separately" do
      stub_request(:get, url).to_return(status: 404, body: "x")
      2.times { call_get }
      stub_request(:post, "https://api.widgets.test/v1/widgets").to_return(status: 404, body: "x")
      result = Connectors::Executor.call(connector: connector, operation: "create_widget", params: { "title" => "a" })

      expect(result.error).not_to include("propose_connector_fix")
    end
  end
end
