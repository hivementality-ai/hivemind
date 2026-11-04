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

    context "with OAuth token (default: auto-routes through SDK proxy)" do
      let(:adapter) { described_class.new(config: config, api_key: "sk-ant-oat-test-token") }
      let(:proxy_client) { instance_double(Providers::Anthropic::SdkProxyClient) }

      before do
        allow(Providers::Anthropic::SdkProxyClient).to receive(:new).and_return(proxy_client)
        allow(proxy_client).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: "proxy response", usage: {} })
        )
      end

      it "auto-detects the OAuth token and delegates to SdkProxyClient" do
        result = adapter.chat(messages: [ { role: "user", content: "Hi" } ])

        expect(result).to be_success
        expect(result.data[:content]).to eq("proxy response")
        expect(proxy_client).to have_received(:chat)
      end
    end

    context "with OAuth token but proxy explicitly disabled" do
      let(:adapter) { described_class.new(config: config, api_key: "sk-ant-oat-test-token") }

      before do
        allow(Setting).to receive(:get).and_call_original
        allow(Setting).to receive(:get).with("anthropic_use_sdk_proxy").and_return("false")
      end

      it "respects the opt-out and delegates to FaradayClient" do
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
        expect(result.data[:usage][:request_payload][:model]).to eq(LlmModelRegistry::Anthropic::DEFAULT_MID)
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
      expect(tool_msg[:content]).to eq([ { type: "tool_result", tool_use_id: "call_1", content: "file.txt", cache_control: { type: "ephemeral" } } ])
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
        { type: "tool_use", id: "tc_1", name: "shell", input: { "command" => "ls" }, cache_control: { type: "ephemeral" } }
      )
    end

    it "formats tools with input_schema" do
      tools = [ { name: "shell", description: "Run command", input_schema: { type: "object" } } ]

      params = adapter.send(:build_chat_params, messages: [ { role: "user", content: "Hi" } ], tools: tools, options: {})

      expect(params[:tools]).to eq([
        { name: "shell", description: "Run command", input_schema: { type: "object" }, cache_control: { type: "ephemeral" } }
      ])
    end

    describe "prompt caching" do
      let(:tools) do
        [ "web_search", "shell", "memory_store" ].map do |name|
          { name: name, description: "#{name} tool", input_schema: { type: "object" } }
        end
      end
      let(:system_blocks) do
        [ { type: "text", text: "core identity " * 20 }, { type: "text", text: "skills" }, { type: "text", text: "memory recall" } ]
      end

      def params_for(messages, tools: self.tools)
        adapter.send(:build_chat_params, messages: messages, tools: tools, options: {})
      end

      def breakpoints(params)
        found = []
        found.concat(params[:tools].select { |t| t[:cache_control] }) if params[:tools]
        found.concat(params[:system].select { |b| b[:cache_control] }) if params[:system]
        params[:messages].each do |m|
          Array(m[:content]).each { |b| found << b if b.is_a?(Hash) && b[:cache_control] }
        end
        found
      end

      it "sorts tools by name regardless of input order" do
        params = params_for([ { role: "user", content: "Hi" } ])

        expect(params[:tools].map { |t| t[:name] }).to eq(%w[memory_store shell web_search])
      end

      it "places a breakpoint on the last tool only" do
        params = params_for([ { role: "user", content: "Hi" } ])

        expect(params[:tools].map { |t| t.key?(:cache_control) }).to eq([ false, false, true ])
      end

      it "places a breakpoint on the last message when content is a string" do
        params = params_for([ { role: "user", content: "first" }, { role: "assistant", content: "ok" }, { role: "user", content: "second" } ])

        expect(params[:messages][0][:content]).to eq("first")
        expect(params[:messages][1][:content]).to eq("ok")
        expect(params[:messages].last[:content]).to eq([ { type: "text", text: "second", cache_control: { type: "ephemeral" } } ])
      end

      it "places the message breakpoint on the last block of array content without mutating the input" do
        blocks = [ { type: "text", text: "look" }, { type: "tool_result", tool_use_id: "t1", content: "done" } ]
        params = params_for([ { role: "user", content: blocks } ])

        expect(params[:messages].last[:content].last).to include(cache_control: { type: "ephemeral" })
        expect(params[:messages].last[:content].first).not_to have_key(:cache_control)
        expect(blocks.last).not_to have_key(:cache_control)
      end

      it "places the message breakpoint on a tool_result for tool messages" do
        params = params_for([ { role: "user", content: "Run" }, { role: "tool", tool_use_id: "c1", content: "out" } ])

        expect(params[:messages].last[:content].last).to include(type: "tool_result", cache_control: { type: "ephemeral" })
      end

      it "skips the message breakpoint for blank content" do
        params = params_for([ { role: "user", content: "" } ], tools: [])

        expect(breakpoints(params)).to be_empty
      end

      it "never exceeds four breakpoints and marks the last system block" do
        params = params_for([ { role: "system", content: system_blocks }, { role: "user", content: "Hi" } ])

        expect(breakpoints(params).size).to eq(4)
        expect(params[:system].last).to have_key(:cache_control)
        expect(params[:system].first).to have_key(:cache_control)
        expect(params[:system][1]).not_to have_key(:cache_control)
      end

      it "builds a byte-identical tools and system prefix across two turns" do
        turn1 = [ { role: "system", content: system_blocks }, { role: "user", content: "Hi" } ]
        turn2 = turn1 + [ { role: "assistant", content: "Hello" }, { role: "user", content: "More" } ]

        first = params_for(turn1)
        second = params_for(turn2, tools: tools.reverse)

        expect(second[:tools].to_json).to eq(first[:tools].to_json)
        expect(second[:system].to_json).to eq(first[:system].to_json)
      end

      it "leaves earlier messages unmarked so the prior turn is a stable prefix" do
        turn = [ { role: "user", content: "Hi" }, { role: "assistant", content: "Hello" }, { role: "user", content: "More" } ]

        expect(params_for(turn)[:messages].first).to eq({ role: "user", content: "Hi" })
      end
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

      expect(params[:model]).to eq(LlmModelRegistry::Anthropic::DEFAULT_MID)
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

    it "caps system breakpoints at two: the last block and the longest earlier one" do
      content = [ { text: "short" }, { text: "the longest stable block" }, { text: "mid size" }, { text: "memory" } ]

      result = adapter.send(:build_cached_system, content)

      expect(result.map { |b| b.key?(:cache_control) }).to eq([ false, true, false, true ])
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

    it "returns the registry's supported Anthropic models" do
      result = adapter.models

      expect(result).to be_success
      expect(result.data[:models]).to eq(LlmModelRegistry.supported_for_provider("anthropic").map(&:api_id))
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
