# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::AnthropicAdapter, type: :service do
  let(:config) { double("Config", base_url: nil) }

  describe "routing" do
    let(:faraday_client) { instance_double(Providers::Anthropic::FaradayClient) }

    before do
      allow(Providers::Anthropic::FaradayClient).to receive(:new).and_return(faraday_client)
      allow(faraday_client).to receive(:chat).and_return(
        ServiceResponse.success(data: { content: "faraday response", usage: {} })
      )
    end

    context "with OAuth token (default flag off)" do
      let(:adapter) { described_class.new(config: config, api_key: "sk-ant-oat-test-token") }

      it "delegates to FaradayClient, not SdkProxyClient" do
        expect(Providers::Anthropic::SdkProxyClient).not_to receive(:new)

        result = adapter.chat(messages: [ { role: "user", content: "Hi" } ])

        expect(result).to be_success
        expect(result.data[:content]).to eq("faraday response")
        expect(faraday_client).to have_received(:chat)
      end
    end

    context "with OAuth token and USE_SDK_PROXY_FALLBACK=true" do
      let(:adapter) { described_class.new(config: config, api_key: "sk-ant-oat-test-token") }
      let(:proxy_client) { instance_double(Providers::Anthropic::SdkProxyClient) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("USE_SDK_PROXY_FALLBACK").and_return("true")
        allow(Providers::Anthropic::SdkProxyClient).to receive(:new).and_return(proxy_client)
        allow(proxy_client).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: "proxy response", usage: {} })
        )
      end

      it "delegates to SdkProxyClient" do
        result = adapter.chat(messages: [ { role: "user", content: "Hi" } ])

        expect(result).to be_success
        expect(result.data[:content]).to eq("proxy response")
        expect(proxy_client).to have_received(:chat)
      end
    end

    context "with API key" do
      let(:adapter) { described_class.new(config: config, api_key: "sk-ant-api-test-key") }

      it "delegates to FaradayClient" do
        result = adapter.chat(messages: [ { role: "user", content: "Hi" } ])

        expect(result).to be_success
        expect(result.data[:content]).to eq("faraday response")
        expect(faraday_client).to have_received(:chat)
      end

      it "injects request_payload into usage" do
        allow(faraday_client).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: "test", usage: { input_tokens: 10 } })
        )

        result = adapter.chat(messages: [ { role: "user", content: "Hi" } ])

        expect(result.data[:usage][:request_payload]).to be_a(Hash)
        expect(result.data[:usage][:request_payload][:model]).to eq("claude-sonnet-4-5")
      end
    end

    context "error handling" do
      let(:adapter) { described_class.new(config: config, api_key: "sk-ant-api-test-key") }

      it "wraps exceptions in failure response" do
        allow(faraday_client).to receive(:chat).and_raise(StandardError, "connection refused")

        result = adapter.chat(messages: [ { role: "user", content: "Hi" } ])

        expect(result).not_to be_success
        expect(result.error).to include("Anthropic API error: connection refused")
      end
    end
  end

  describe "#build_chat_params" do
    let(:adapter) { described_class.new(config: config, api_key: "sk-ant-api-test") }

    it "extracts system message and formats it with cache_control" do
      messages = [
        { role: "system", content: "Be helpful" },
        { role: "user", content: "Hello" }
      ]

      params = adapter.send(:build_chat_params, messages: messages, tools: [], options: {})

      expect(params[:system]).to eq([
        { type: "text", text: "Be helpful", cache_control: { type: "ephemeral" } }
      ])
      expect(params[:messages].none? { |m| m[:role] == "system" }).to be true
    end

    it "formats tool messages as tool_result" do
      messages = [
        { role: "user", content: "Run ls" },
        { role: "tool", tool_use_id: "call_1", content: "file.txt" }
      ]

      params = adapter.send(:build_chat_params, messages: messages, tools: [], options: {})

      tool_msg = params[:messages].last
      expect(tool_msg[:role]).to eq("user")
      expect(tool_msg[:content]).to eq([ { type: "tool_result", tool_use_id: "call_1", content: "file.txt" } ])
    end

    it "formats assistant messages with tool_calls" do
      messages = [
        {
          role: "assistant",
          content: "Let me check",
          tool_calls: [ { "id" => "tc_1", "name" => "shell", "input" => { "command" => "ls" } } ]
        }
      ]

      params = adapter.send(:build_chat_params, messages: messages, tools: [], options: {})

      assistant_msg = params[:messages].first
      expect(assistant_msg[:role]).to eq("assistant")
      expect(assistant_msg[:content]).to include(
        { type: "text", text: "Let me check" },
        { type: "tool_use", id: "tc_1", name: "shell", input: { "command" => "ls" } }
      )
    end

    it "formats tools with input_schema" do
      tools = [ { name: "shell", description: "Run command", input_schema: { type: "object" } } ]

      params = adapter.send(:build_chat_params, messages: [ { role: "user", content: "Hi" } ], tools: tools, options: {})

      expect(params[:tools]).to eq([
        { name: "shell", description: "Run command", input_schema: { type: "object" } }
      ])
    end

    it "sets thinking params and adjusts max_tokens" do
      options = { thinking_enabled: true, thinking_budget_tokens: 5000 }

      params = adapter.send(:build_chat_params, messages: [ { role: "user", content: "Hi" } ], tools: [], options: options)

      expect(params[:thinking]).to eq({ type: "enabled", budget_tokens: 5000 })
      expect(params[:max_tokens]).to eq(9096) # 5000 + 4096
      expect(params).not_to have_key(:temperature)
    end

    it "uses default model and max_tokens" do
      params = adapter.send(:build_chat_params, messages: [ { role: "user", content: "Hi" } ], tools: [], options: {})

      expect(params[:model]).to eq("claude-sonnet-4-5")
      expect(params[:max_tokens]).to eq(8192)
    end

    it "respects custom model and temperature" do
      options = { model: "claude-opus-4-6", temperature: 0.5 }

      params = adapter.send(:build_chat_params, messages: [ { role: "user", content: "Hi" } ], tools: [], options: options)

      expect(params[:model]).to eq("claude-opus-4-6")
      expect(params[:temperature]).to eq(0.5)
    end
  end

  describe "#build_cached_system" do
    let(:adapter) { described_class.new(config: config, api_key: "sk-ant-api-test") }

    it "wraps string content in cached text block" do
      result = adapter.send(:build_cached_system, "System prompt")

      expect(result).to eq([
        { type: "text", text: "System prompt", cache_control: { type: "ephemeral" } }
      ])
    end

    it "wraps array content blocks" do
      content = [ { text: "Block 1" }, { text: "Block 2" } ]

      result = adapter.send(:build_cached_system, content)

      expect(result).to eq([
        { type: "text", text: "Block 1", cache_control: { type: "ephemeral" } },
        { type: "text", text: "Block 2", cache_control: { type: "ephemeral" } }
      ])
    end

    it "rejects blank text blocks" do
      content = [ { text: "Keep" }, { text: "" }, { text: nil } ]

      result = adapter.send(:build_cached_system, content)

      expect(result).to eq([
        { type: "text", text: "Keep", cache_control: { type: "ephemeral" } }
      ])
    end
  end

  describe "#models" do
    let(:adapter) { described_class.new(config: config, api_key: "sk-ant-api-test") }

    it "returns static model list" do
      result = adapter.models

      expect(result).to be_success
      expect(result.data[:models]).to eq(%w[claude-haiku-4-5 claude-sonnet-4-5 claude-opus-4-6])
    end
  end

  describe "#embed" do
    let(:adapter) { described_class.new(config: config, api_key: "sk-ant-api-test") }

    it "returns failure" do
      result = adapter.embed(text: "test")

      expect(result).not_to be_success
      expect(result.error).to include("does not support embeddings")
    end
  end

  describe "#sanitize_payload_for_logging" do
    let(:adapter) { described_class.new(config: config, api_key: "sk-ant-api-test") }

    it "truncates long string content" do
      long_content = "x" * 3000
      params = { messages: [ { role: "user", content: long_content } ] }

      result = adapter.send(:sanitize_payload_for_logging, params)

      expect(result[:messages].first[:content].length).to be < 3000
      expect(result[:messages].first[:content]).to include("[truncated")
    end

    it "truncates long text in array content blocks" do
      long_text = "y" * 3000
      params = { messages: [ { role: "user", content: [ { type: "text", text: long_text } ] } ] }

      result = adapter.send(:sanitize_payload_for_logging, params)

      expect(result[:messages].first[:content].first[:text].length).to be < 3000
    end

    it "removes request_options" do
      params = { messages: [], request_options: { timeout: 30 } }

      result = adapter.send(:sanitize_payload_for_logging, params)

      expect(result).not_to have_key(:request_options)
    end
  end
end
