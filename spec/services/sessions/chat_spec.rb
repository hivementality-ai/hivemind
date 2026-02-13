# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sessions::Chat do
  describe '.call' do
    let(:agent) { create(:agent, model_provider: "openai", llm_model: "gpt-4") }
    let(:session) { create(:session, agent: agent, input_tokens: 100, output_tokens: 50, total_tokens: 150) }
    let(:message) { "How do I deploy my Rails application to production?" }
    let(:assistant_response) { "To deploy a Rails application to production, you need to..." }
    let(:usage_data) { { input_tokens: 150, output_tokens: 80 } }

    let(:mock_adapter) { double('adapter') }
    let(:mock_resolver) { ServiceResponse.success(data: { adapter: mock_adapter }) }

    before do
      # Mock Providers::Resolver
      allow(Providers::Resolver).to receive(:call).and_return(mock_resolver)
      
      # Mock adapter.chat response
      allow(mock_adapter).to receive(:chat).and_return(
        ServiceResponse.success(data: { content: assistant_response, usage: usage_data })
      )
      
      # Mock memory-related operations
      allow(MemoryEntry).to receive(:where).and_return(double(
        where: double(order: double(limit: [])),
        order: double(limit: [])
      ))
      allow(MemoryEntry).to receive(:create)

      # Mock CostEstimator
      allow(CostEstimator).to receive(:estimate).and_return(25)

      # Mock Rails.logger
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
    end

    describe 'successful chat completion' do
      it 'processes chat message and returns response' do
        result = described_class.call(session: session, message: message)

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:content]).to eq(assistant_response)
        expect(result.data[:usage]).to eq(usage_data)
      end

      it 'appends user message to transcript' do
        expect(session).to receive(:append_transcript).with({ "role" => "user", "content" => message })

        described_class.call(session: session, message: message)
      end

      it 'appends assistant response to transcript' do
        expect(session).to receive(:append_transcript).with({ "role" => "assistant", "content" => assistant_response })

        described_class.call(session: session, message: message)
      end

      it 'resolves the provider adapter' do
        described_class.call(session: session, message: message)

        expect(Providers::Resolver).to have_received(:call).with(
          provider_name: agent.model_provider,
          agent: agent
        )
      end

      it 'calls adapter with correct parameters' do
        described_class.call(session: session, message: message)

        expect(mock_adapter).to have_received(:chat) do |args|
          expect(args[:messages]).to be_an(Array)
          expect(args[:options]).to eq({ model: agent.llm_model })
        end
      end

      it 'updates session token counts' do
        original_input = session.input_tokens
        original_output = session.output_tokens
        original_total = session.total_tokens

        described_class.call(session: session, message: message)

        session.reload
        expect(session.input_tokens).to eq(original_input + usage_data[:input_tokens])
        expect(session.output_tokens).to eq(original_output + usage_data[:output_tokens])
        expect(session.total_tokens).to eq(original_total + usage_data[:input_tokens] + usage_data[:output_tokens])
      end

      it 'records usage for tracking' do
        expect {
          described_class.call(session: session, message: message)
        }.to change(UsageRecord, :count).by(1)

        usage_record = UsageRecord.last
        expect(usage_record.agent).to eq(agent)
        expect(usage_record.session).to eq(session)
        expect(usage_record.provider).to eq(agent.model_provider)
        expect(usage_record.llm_model).to eq(agent.llm_model)
        expect(usage_record.input_tokens).to eq(usage_data[:input_tokens])
        expect(usage_record.output_tokens).to eq(usage_data[:output_tokens])
        expect(usage_record.cost_cents).to eq(25)
      end
    end

    describe 'streaming chat' do
      let(:chunks) { ["To deploy", " a Rails app", "..."] }
      let(:received_chunks) { [] }

      it 'handles streaming responses' do
        allow(mock_adapter).to receive(:chat) do |args, &block|
          chunks.each { |chunk| block.call(chunk) } if block
          ServiceResponse.success(data: { content: assistant_response, usage: usage_data })
        end

        result = described_class.call(
          session: session,
          message: message,
          stream: true
        ) { |chunk| received_chunks << chunk }

        expect(result.success?).to be true
        expect(received_chunks).to eq(chunks)
        expect(mock_adapter).to have_received(:chat) do |args, &block|
          expect(block).to be_present
        end
      end

      it 'works without streaming when block not provided' do
        result = described_class.call(
          session: session,
          message: message,
          stream: true
        )

        expect(result.success?).to be true
        expect(mock_adapter).to have_received(:chat) do |args, &block|
          expect(block).to be_nil
        end
      end

      it 'does not stream when stream is false' do
        described_class.call(session: session, message: message, stream: false)

        expect(mock_adapter).to have_received(:chat) do |args, &block|
          expect(block).to be_nil
        end
      end
    end

    describe 'memory recall' do
      let!(:relevant_memory) do
        create(:memory_entry,
               agent: agent,
               content: "User previously asked about deployment strategies",
               created_at: 2.days.ago)
      end
      let!(:recent_memory) do
        create(:memory_entry,
               agent: agent,
               content: "User prefers React for frontend",
               created_at: 1.hour.ago)
      end
      let!(:other_agent_memory) do
        create(:memory_entry,
               content: "Should not be included",
               created_at: 1.day.ago)
      end

      before do
        # Reset the MemoryEntry mocking to use real database
        allow(MemoryEntry).to receive(:where).and_call_original
        allow(MemoryEntry).to receive(:create).and_call_original
      end

      it 'recalls relevant memories for context' do
        result = described_class.call(session: session, message: "deployment rails")

        # Should have called the LLM with system prompt containing memories
        expect(mock_adapter).to have_received(:chat) do |args|
          messages = args[:messages]
          system_message = messages.find { |m| m[:role] == "system" }
          expect(system_message[:content]).to include("Your Memories")
        end
      end

      it 'includes memories in system prompt' do
        service = described_class.new(session: session, message: message)
        memories = [relevant_memory, recent_memory]
        
        system_prompt = service.send(:build_system_prompt, agent: agent, memories: memories)
        
        expect(system_prompt).to include("Your Memories")
        expect(system_prompt).to include(relevant_memory.content)
        expect(system_prompt).to include(recent_memory.content)
      end

      it 'handles memory recall failures gracefully' do
        allow(MemoryEntry).to receive(:where).and_raise(StandardError, "Database error")

        result = described_class.call(session: session, message: message)

        expect(result.success?).to be true
        expect(Rails.logger).to have_received(:warn).with(/Memory recall failed/)
      end
    end

    describe 'memory storage' do
      before do
        allow(MemoryEntry).to receive(:create).and_call_original
      end

      it 'stores meaningful conversation exchanges' do
        long_message = "This is a detailed question about deployment strategies that should be stored in memory"
        
        expect {
          described_class.call(session: session, message: long_message)
        }.to change(MemoryEntry, :count).by(1)

        memory_entry = MemoryEntry.last
        expect(memory_entry.agent).to eq(agent)
        expect(memory_entry.content).to include("User asked:")
        expect(memory_entry.content).to include(long_message.truncate(200))
        expect(memory_entry.content).to include("Agent responded:")
        expect(memory_entry.content).to include(assistant_response.truncate(500))
        expect(memory_entry.source).to eq(session)
        expect(memory_entry.metadata["session_id"]).to eq(session.id)
      end

      it 'skips storing short greetings' do
        short_message = "Hi"
        short_response = "Hello!"
        
        allow(mock_adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: short_response, usage: usage_data })
        )

        expect {
          described_class.call(session: session, message: short_message)
        }.not_to change(MemoryEntry, :count)
      end

      it 'handles memory storage failures gracefully' do
        allow(MemoryEntry).to receive(:create).and_raise(StandardError, "Storage error")

        result = described_class.call(session: session, message: message)

        expect(result.success?).to be true
        expect(Rails.logger).to have_received(:warn).with(/Memory storage failed/)
      end
    end

    describe 'message building' do
      let(:session_with_transcript) do
        create(:session, agent: agent, transcript: [
          { "role" => "user", "content" => "Previous question" },
          { "role" => "assistant", "content" => "Previous answer" }
        ])
      end

      it 'builds messages from transcript and memories' do
        service = described_class.new(session: session_with_transcript, message: message)
        memories = [create(:memory_entry, agent: agent, content: "Test memory")]
        
        messages = service.send(:build_messages, agent: agent, memories: memories)
        
        # Should have system message + transcript messages
        expect(messages).to be_an(Array)
        expect(messages.length).to be >= 3 # system + 2 from transcript
        
        system_message = messages.find { |m| m[:role] == "system" }
        expect(system_message).to be_present
        expect(system_message[:content]).to include("Test memory")

        user_messages = messages.select { |m| m[:role] == "user" }
        expect(user_messages.length).to eq(1)
        expect(user_messages.first[:content]).to eq("Previous question")
      end

      it 'limits transcript to last 50 messages' do
        # Create a transcript with more than 50 messages
        large_transcript = Array.new(60) do |i|
          { "role" => i.even? ? "user" : "assistant", "content" => "Message #{i}" }
        end
        
        session_with_large_transcript = create(:session, agent: agent, transcript: large_transcript)
        service = described_class.new(session: session_with_large_transcript, message: message)
        
        messages = service.send(:build_messages, agent: agent, memories: [])
        
        # Should have system message + last 50 transcript messages
        transcript_messages = messages.reject { |m| m[:role] == "system" }
        expect(transcript_messages.length).to eq(50)
        expect(transcript_messages.last[:content]).to eq("Message 59")
      end

      it 'includes agent system prompt in system message' do
        agent.update(system_prompt: "You are a helpful assistant")
        service = described_class.new(session: session, message: message)
        
        system_prompt = service.send(:build_system_prompt, agent: agent, memories: [])
        
        expect(system_prompt).to include("You are a helpful assistant")
      end
    end

    describe 'error handling' do
      context 'when provider resolver fails' do
        let(:resolver_failure) { ServiceResponse.failure(error: "Provider not found") }

        before do
          allow(Providers::Resolver).to receive(:call).and_return(resolver_failure)
        end

        it 'returns the resolver failure' do
          result = described_class.call(session: session, message: message)

          expect(result.success?).to be false
          expect(result.error).to eq("Provider not found")
        end

        it 'does not call the adapter' do
          described_class.call(session: session, message: message)

          expect(mock_adapter).not_to have_received(:chat)
        end
      end

      context 'when adapter chat fails' do
        let(:chat_failure) { ServiceResponse.failure(error: "API rate limit exceeded") }

        before do
          allow(mock_adapter).to receive(:chat).and_return(chat_failure)
        end

        it 'returns the chat failure' do
          result = described_class.call(session: session, message: message)

          expect(result.success?).to be false
          expect(result.error).to eq("API rate limit exceeded")
        end

        it 'does not update session tokens' do
          original_tokens = session.total_tokens

          described_class.call(session: session, message: message)

          session.reload
          expect(session.total_tokens).to eq(original_tokens)
        end
      end

      context 'when usage recording fails' do
        before do
          allow(UsageRecord).to receive(:create).and_raise(StandardError, "Database error")
        end

        it 'continues successfully and logs warning' do
          result = described_class.call(session: session, message: message)

          expect(result.success?).to be true
          expect(Rails.logger).to have_received(:warn).with(/Failed to record usage/)
        end
      end

      context 'when session update fails' do
        before do
          allow(session).to receive(:update!).and_raise(ActiveRecord::RecordInvalid, "Validation failed")
        end

        it 'returns failure with error message' do
          result = described_class.call(session: session, message: message)

          expect(result.success?).to be false
          expect(result.error).to eq("Validation failed")
          expect(Rails.logger).to have_received(:error).with(/Error: Validation failed/)
        end
      end

      context 'when an unexpected error occurs' do
        before do
          allow(session).to receive(:append_transcript).and_raise(StandardError, "Unexpected error")
        end

        it 'returns failure with error message' do
          result = described_class.call(session: session, message: message)

          expect(result.success?).to be false
          expect(result.error).to eq("Unexpected error")
          expect(Rails.logger).to have_received(:error).with(/Error: Unexpected error/)
        end
      end
    end

    describe 'usage data handling' do
      context 'when usage data is missing' do
        before do
          allow(mock_adapter).to receive(:chat).and_return(
            ServiceResponse.success(data: { content: assistant_response })
          )
        end

        it 'handles missing usage data gracefully' do
          result = described_class.call(session: session, message: message)

          expect(result.success?).to be true
          
          # Should use 0 for missing token counts
          usage_record = UsageRecord.last
          expect(usage_record.input_tokens).to eq(0)
          expect(usage_record.output_tokens).to eq(0)
        end

        it 'does not update session token counts when usage missing' do
          original_tokens = session.total_tokens

          described_class.call(session: session, message: message)

          session.reload
          expect(session.total_tokens).to eq(original_tokens)
        end
      end

      context 'when usage data has partial information' do
        let(:partial_usage) { { input_tokens: 100 } } # Missing output_tokens

        before do
          allow(mock_adapter).to receive(:chat).and_return(
            ServiceResponse.success(data: { content: assistant_response, usage: partial_usage })
          )
        end

        it 'uses 0 for missing token counts' do
          described_class.call(session: session, message: message)

          usage_record = UsageRecord.last
          expect(usage_record.input_tokens).to eq(100)
          expect(usage_record.output_tokens).to eq(0)
        end
      end
    end

    describe 'query sanitization' do
      let(:service) { described_class.new(session: session, message: message) }

      it 'sanitizes queries for ILIKE search' do
        dirty_query = "How do I deploy my app? It's <critical>!"
        sanitized = service.send(:sanitize_query, dirty_query)
        
        # Should remove special characters and keep only long words
        expect(sanitized).to include("deploy")
        expect(sanitized).not_to include("<")
        expect(sanitized).not_to include(">")
        expect(sanitized).not_to include("?")
        expect(sanitized).not_to include("It's") # Too short
      end

      it 'limits to first 3 meaningful terms' do
        long_query = "How do I deploy my rails application using docker containers with nginx proxy server"
        sanitized = service.send(:sanitize_query, long_query)
        
        terms = sanitized.split("%")
        expect(terms.length).to be <= 3
      end

      it 'handles empty queries' do
        empty_query = "!@# $%^"
        sanitized = service.send(:sanitize_query, empty_query)
        
        expect(sanitized).to be_a(String)
        expect(sanitized).to eq("")
      end
    end
  end
end