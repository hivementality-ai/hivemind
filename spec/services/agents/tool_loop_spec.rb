# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::ToolLoop do
  describe '.call' do
    let(:agent) { create(:agent) }
    let(:session) { create(:session, agent: agent) }
    let(:channel) { "test_channel" }
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:tools) { [double("tool", name: "test_tool", to_llm_tool: { name: "test_tool" })] }
    let(:adapter) { double("adapter") }
    let(:options) { {} }
    let(:broadcast_extras) { { session_id: session.id } }

    before do
      # Mock ActionCable.server.broadcast
      allow(ActionCable.server).to receive(:broadcast)
      # Mock Tools::Executor
      allow(Tools::Executor).to receive(:call).and_return(
        ServiceResponse.success(data: { output: "Tool executed successfully" })
      )
    end

    describe 'simple conversation without tools' do
      it 'returns the final response content' do
        # Mock LLM response without tool calls
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: {
            content: "Hello! How can I help you?",
            usage: { input_tokens: 10, output_tokens: 8 }
          })
        )

        result = described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:content]).to eq("Hello! How can I help you?")
        expect(result.data[:usage]).to eq({ input_tokens: 10, output_tokens: 8 })
      end

      it 'broadcasts token updates' do
        response_content = "Hello! How can I help you?"
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: response_content })
        )

        described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel,
          broadcast_extras: broadcast_extras
        )

        expect(ActionCable.server).to have_received(:broadcast).with(
          channel,
          broadcast_extras.merge(type: "token", content: response_content)
        )
      end
    end

    describe 'conversation with tool calls' do
      let(:tool_calls) do
        [{
          "id" => "call_123",
          "name" => "test_tool",
          "input" => { "query" => "test" }
        }]
      end

      it 'executes tools and continues conversation' do
        # First call returns tool calls
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: {
            content: "I'll use a tool to help.",
            tool_calls: tool_calls,
            usage: { input_tokens: 15, output_tokens: 5 }
          }),
          ServiceResponse.success(data: {
            content: "Based on the tool result, here's my answer.",
            usage: { input_tokens: 20, output_tokens: 10 }
          })
        )

        result = described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )

        expect(result.success?).to be true
        expect(result.data[:content]).to eq("Based on the tool result, here's my answer.")
        expect(result.data[:usage]).to eq({ input_tokens: 35, output_tokens: 15 })

        # Should be called twice - once for tool call, once for final response
        expect(adapter).to have_received(:chat).twice
      end

      it 'broadcasts tool execution updates' do
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: {
            content: "Using tool.",
            tool_calls: tool_calls
          }),
          ServiceResponse.success(data: { content: "Final answer." })
        )

        described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel,
          broadcast_extras: broadcast_extras
        )

        expect(ActionCable.server).to have_received(:broadcast).with(
          channel,
          broadcast_extras.merge(
            type: "tool_start",
            tool: "test_tool",
            input: { "query" => "test" }
          )
        )

        expect(ActionCable.server).to have_received(:broadcast).with(
          channel,
          broadcast_extras.merge(
            type: "tool_result",
            tool: "test_tool",
            output: "Tool executed successfully",
            success: true
          )
        )
      end

      it 'adds tool calls and results to message history' do
        allow(adapter).to receive(:chat) do |args|
          messages = args[:messages]
          
          if messages.length == 1  # Initial call
            ServiceResponse.success(data: {
              content: "Using tool.",
              tool_calls: tool_calls
            })
          else
            # Verify that tool call and result were added to messages
            expect(messages[-2][:role]).to eq("assistant")
            expect(messages[-2][:tool_calls]).to eq(tool_calls)
            expect(messages[-1][:role]).to eq("tool")
            expect(messages[-1][:tool_use_id]).to eq("call_123")
            expect(messages[-1][:content]).to eq("Tool executed successfully")
            
            ServiceResponse.success(data: { content: "Final answer." })
          end
        end

        described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )
      end
    end

    describe 'tool execution errors' do
      let(:tool_calls) do
        [{
          "id" => "call_123",
          "name" => "test_tool",
          "input" => {}
        }]
      end

      it 'handles tool execution failures' do
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: {
            tool_calls: tool_calls
          }),
          ServiceResponse.success(data: { content: "I encountered an error." })
        )

        # Mock tool execution failure
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.failure(error: "Tool execution failed")
        )

        result = described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )

        expect(result.success?).to be true # Service succeeds even if tools fail

        # Should broadcast tool failure
        expect(ActionCable.server).to have_received(:broadcast).with(
          channel,
          hash_including(
            type: "tool_result",
            tool: "test_tool",
            output: "Error: Tool execution failed",
            success: false
          )
        )
      end

      it 'handles unknown tool calls' do
        unknown_tool_calls = [{
          "id" => "call_123",
          "name" => "unknown_tool",
          "input" => {}
        }]

        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { tool_calls: unknown_tool_calls }),
          ServiceResponse.success(data: { content: "I encountered an error." })
        )

        result = described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )

        expect(result.success?).to be true

        # Should broadcast unknown tool error
        expect(ActionCable.server).to have_received(:broadcast).with(
          channel,
          hash_including(
            type: "tool_result",
            tool: "unknown_tool",
            output: "Error: Unknown tool 'unknown_tool'",
            success: false
          )
        )
      end
    end

    describe 'max iterations limit' do
      it 'stops after MAX_ITERATIONS and broadcasts warning' do
        # Mock adapter to always return tool calls (infinite loop scenario)
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: {
            tool_calls: [{
              "id" => "call_123",
              "name" => "test_tool",
              "input" => {}
            }]
          })
        )

        result = described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )

        expect(result.success?).to be true
        expect(adapter).to have_received(:chat).exactly(described_class::MAX_ITERATIONS).times
        
        # Should broadcast limit warning
        expect(ActionCable.server).to have_received(:broadcast).with(
          channel,
          hash_including(
            type: "token",
            content: "\n\n⚠️ Tool loop limit reached (10 iterations)"
          )
        )
      end
    end

    describe 'thinking capture' do
      it 'captures and returns thinking from LLM response' do
        thinking_content = "I need to consider this carefully..."
        
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: {
            content: "Final answer",
            thinking: thinking_content
          })
        )

        result = described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )

        expect(result.data[:thinking]).to eq(thinking_content)
      end
    end

    describe 'error handling' do
      context 'when LLM call fails' do
        it 'returns failure with error message' do
          allow(adapter).to receive(:chat).and_raise(StandardError, "Network timeout")

          result = described_class.call(
            adapter: adapter,
            agent: agent,
            session: session,
            messages: messages,
            tools: tools,
            channel: channel
          )

          expect(result.success?).to be false
          expect(result.error).to eq("LLM call failed: Network timeout")
        end
      end

      context 'when adapter returns failure' do
        it 'returns the adapter failure' do
          allow(adapter).to receive(:chat).and_return(
            ServiceResponse.failure(error: "Invalid API key")
          )

          result = described_class.call(
            adapter: adapter,
            agent: agent,
            session: session,
            messages: messages,
            tools: tools,
            channel: channel
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Invalid API key")
        end
      end
    end

    describe 'empty content handling' do
      it 'handles empty LLM responses gracefully' do
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: {
            content: "",
            usage: { input_tokens: 5, output_tokens: 0 }
          })
        )

        result = described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )

        expect(result.success?).to be true
        expect(result.data[:content]).to eq("")
      end
    end

    describe 'message immutability' do
      it 'does not modify the original messages array' do
        original_messages = messages.dup
        
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: "Response" })
        )

        described_class.call(
          adapter: adapter,
          agent: agent,
          session: session,
          messages: messages,
          tools: tools,
          channel: channel
        )

        expect(messages).to eq(original_messages)
      end
    end
  end
end