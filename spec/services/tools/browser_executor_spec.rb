# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::BrowserExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    allow(SecureRandom).to receive(:hex).and_return('12345678')
    allow(File).to receive(:write)
    allow(FileUtils).to receive(:rm_f)
  end

  describe '#call' do
    context 'with navigate action' do
      let(:input) { { "action" => "navigate", "url" => "https://example.com" } }

      before do
        mock_browser_response({
          success: true,
          title: "Example Domain",
          url: "https://example.com",
          content: "This domain is for use in illustrative examples."
        })
      end

      it 'returns success with page content' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Title: Example Domain")
        expect(result.data[:output]).to include("URL: https://example.com")
        expect(result.data[:output]).to include("This domain is for use in illustrative examples.")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'writes script to temp file' do
        executor.call
        expect(File).to have_received(:write).with('/tmp/browser_script_12345678.js', anything)
      end

      it 'cleans up temp file' do
        executor.call
        expect(FileUtils).to have_received(:rm_f).with('/tmp/browser_script_12345678.js')
      end

      it 'executes docker command' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          "docker", "exec", "-i", "hivemind-browser-1",
          "node", "-e", anything,
          timeout: 35
        )
      end
    end

    context 'with get action (alias for navigate)' do
      let(:input) { { "action" => "get", "url" => "https://example.com" } }

      before do
        mock_browser_response({
          success: true,
          title: "Example Domain",
          url: "https://example.com",
          content: "Test content"
        })
      end

      it 'works as navigate alias' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Title: Example Domain")
      end
    end

    context 'with empty action (defaults to navigate)' do
      let(:input) { { "url" => "https://example.com" } }

      before do
        mock_browser_response({
          success: true,
          title: "Example Domain",
          url: "https://example.com",
          content: "Test content"
        })
      end

      it 'defaults to navigate action' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Title: Example Domain")
      end
    end

    context 'with screenshot action' do
      let(:input) { { "action" => "screenshot", "url" => "https://example.com" } }

      before do
        mock_browser_response({
          success: true,
          title: "Example Domain",
          path: "/tmp/screenshot.png"
        })
      end

      it 'returns success with screenshot path' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Screenshot saved: /tmp/screenshot.png")
        expect(result.data[:output]).to include("Title: Example Domain")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'generates correct playwright script' do
        script_content = nil
        allow(File).to receive(:write) do |path, content|
          script_content = content if path.include?('.js')
        end

        executor.call

        expect(script_content).to include("await page.screenshot({ path: '/tmp/screenshot.png', fullPage: false });")
        expect(script_content).to include("await page.goto('https://example.com'")
        expect(script_content).not_to include("const content = await page.evaluate")
      end
    end

    context 'without url parameter' do
      let(:input) { { "action" => "navigate" } }

      it 'returns failure for navigate' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No URL provided")
      end
    end

    context 'with empty url' do
      let(:input) { { "action" => "navigate", "url" => "  " } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No URL provided")
      end
    end

    context 'without url for screenshot' do
      let(:input) { { "action" => "screenshot" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No URL provided")
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "unknown", "url" => "https://example.com" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Unknown browser action: unknown. Supported: navigate, screenshot")
      end
    end

    context 'when browser execution fails' do
      let(:input) { { "action" => "navigate", "url" => "https://example.com" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['', 'Browser error', double(success?: false)])
      end

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Browser error")
      end
    end

    context 'when browser returns error' do
      let(:input) { { "action" => "navigate", "url" => "https://invalid-url" } }

      before do
        mock_browser_response({
          success: false,
          error: "net::ERR_NAME_NOT_RESOLVED"
        })
      end

      it 'returns failure with browser error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("net::ERR_NAME_NOT_RESOLVED")
      end
    end

    context 'when JSON parsing fails' do
      let(:input) { { "action" => "navigate", "url" => "https://example.com" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['invalid json output', '', double(success?: true)])
      end

      it 'returns failure with parsing error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Failed to parse browser output")
      end
    end

    context 'when docker exec raises exception' do
      let(:input) { { "action" => "navigate", "url" => "https://example.com" } }

      before do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("Docker not available"))
      end

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Browser error: Docker not available")
      end
    end

    context 'with large content' do
      let(:input) { { "action" => "navigate", "url" => "https://example.com" } }
      let(:large_content) { 'x' * 40_000 }

      before do
        mock_browser_response({
          success: true,
          title: "Large Page",
          url: "https://example.com",
          content: large_content
        })
      end

      it 'truncates content to 30KB' do
        result = executor.call
        expect(result).to be_success
        content_part = result.data[:output].split("\n\n").last
        expect(content_part.length).to be <= 30_000
      end
    end

    context 'with special characters in URL' do
      let(:input) { { "action" => "navigate", "url" => "https://example.com/path?query='test'" } }

      before do
        mock_browser_response({
          success: true,
          title: "Test Page",
          url: "https://example.com/path?query='test'",
          content: "Test content"
        })
      end

      it 'handles special characters in URL' do
        script_content = nil
        allow(File).to receive(:write) do |path, content|
          script_content = content if path.include?('.js')
        end

        result = executor.call

        expect(result).to be_success
        expect(script_content).to include("await page.goto('https://example.com/path?query=\\\\'test\\\\'")
      end
    end

    context 'with timeout from docker' do
      let(:input) { { "action" => "navigate", "url" => "https://slow-site.com" } }

      before do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("execution expired"))
      end

      it 'handles timeout errors' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Browser error: execution expired")
      end
    end
  end

  private

  def mock_browser_response(response_data)
    json_output = JSON.generate(response_data)
    allow(Open3).to receive(:capture3).and_return([
      "some debug output\n#{json_output}",
      '',
      double(success?: true)
    ])
  end
end