# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::BrowserExecutor, type: :service do
  subject(:executor) { described_class.new(input: input) }

  def build_sidecar_response(body, code: "200")
    instance_double(Net::HTTPSuccess,
      is_a?: true,
      body: body.to_json,
      code: code
    ).tap do |resp|
      allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(code.to_i < 400)
    end
  end

  def stub_sidecar(path, response_body, code: "200")
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)

    resp = instance_double(Net::HTTPResponse)
    allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(code.to_i < 400)
    allow(resp).to receive(:body).and_return(response_body.to_json)
    allow(resp).to receive(:code).and_return(code)

    allow(http).to receive(:request).and_return(resp)
    resp
  end

  describe "#call" do
    context "with no URL" do
      let(:input) { { "action" => "navigate", "url" => "" } }

      it "returns failure immediately without hitting sidecar" do
        expect(Net::HTTP).not_to receive(:new)
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No URL provided")
      end
    end

    context "with unknown action" do
      let(:input) { { "action" => "click", "url" => "https://example.com" } }

      it "returns failure" do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to include("Unknown browser action: click")
      end
    end

    context "navigate action" do
      let(:input) { { "action" => "navigate", "url" => "https://example.com" } }

      it "returns formatted content on success" do
        stub_sidecar("/navigate", {
          success: true,
          title: "Example Domain",
          url: "https://example.com",
          content: "This domain is for use in examples."
        })

        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to include("Title: Example Domain")
        expect(result.data[:output]).to include("URL: https://example.com")
        expect(result.data[:output]).to include("This domain is for use in examples.")
        expect(result.data[:exit_code]).to eq(0)
      end

      it "treats blank action as navigate" do
        input_blank = { "action" => "", "url" => "https://example.com" }
        ex = described_class.new(input: input_blank)
        stub_sidecar("/navigate", { success: true, title: "T", url: "https://example.com", content: "body" })

        result = ex.call
        expect(result).to be_success
      end

      it "treats 'get' action as navigate" do
        input_get = { "action" => "get", "url" => "https://example.com" }
        ex = described_class.new(input: input_get)
        stub_sidecar("/navigate", { success: true, title: "T", url: "https://example.com", content: "body" })

        result = ex.call
        expect(result).to be_success
      end

      it "returns failure when sidecar reports error" do
        stub_sidecar("/navigate", { success: false, error: "Navigation timeout" })

        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to eq("Navigation timeout")
      end

      it "returns failure on non-2xx sidecar response" do
        stub_sidecar("/navigate", { error: "Internal Server Error" }, code: "500")

        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("Browser sidecar error (500)")
      end

      it "returns failure on JSON parse error" do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)

        resp = instance_double(Net::HTTPResponse)
        allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(resp).to receive(:body).and_return("not json {{")
        allow(http).to receive(:request).and_return(resp)

        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to eq("Invalid response from browser sidecar")
      end

      it "returns failure on network error" do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED, "Connection refused")

        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("Browser error:")
      end
    end

    context "screenshot action" do
      let(:input) { { "action" => "screenshot", "url" => "https://example.com" } }

      it "returns screenshot path on success" do
        stub_sidecar("/screenshot", {
          success: true,
          title: "Example Domain",
          url: "https://example.com",
          path: "/tmp/screenshot_123.png"
        })

        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to include("Screenshot saved: /tmp/screenshot_123.png")
        expect(result.data[:output]).to include("Title: Example Domain")
        expect(result.data[:exit_code]).to eq(0)
      end

      it "returns failure when sidecar reports error" do
        stub_sidecar("/screenshot", { success: false, error: "Screenshot failed" })

        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to eq("Screenshot failed")
      end
    end
  end
end
