# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Memory::Store do
  describe '.call' do
    let(:agent) { create(:agent, model_provider: "openai") }
    let(:content) { "The user prefers React over Vue for frontend development" }
    let(:source) { "conversation" }
    let(:metadata) { { session_id: "abc123", confidence: 0.9 } }
    let(:sample_embedding) { Array.new(1536) { rand } }

    before do
      # Mock Faraday HTTP requests
      allow(Faraday).to receive(:post).and_return(
        double(success?: true, body: {
          data: [{ embedding: sample_embedding }]
        }.to_json)
      )

      # Mock VaultEntry for API key
      allow(VaultEntry).to receive(:find_by).with(
        namespace: "provider_credentials",
        key: "openai_api_key"
      ).and_return(double(encrypted_value: "sk-test123"))

      # Mock Rails.logger
      allow(Rails.logger).to receive(:error)
    end

    describe 'successful memory storage' do
      it 'stores memory with embedding successfully' do
        expect {
          result = described_class.call(
            agent: agent,
            content: content,
            source: source,
            metadata: metadata
          )

          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true
          expect(result.data[:memory_entry]).to be_a(MemoryEntry)
        }.to change(MemoryEntry, :count).by(1)

        memory_entry = MemoryEntry.last
        expect(memory_entry.agent).to eq(agent)
        expect(memory_entry.content).to eq(content)
        expect(memory_entry.embedding).to eq(sample_embedding)
        expect(memory_entry.source).to eq(source)
        expect(memory_entry.metadata).to eq(metadata.stringify_keys)
      end

      it 'generates embedding using OpenAI API' do
        described_class.call(agent: agent, content: content, source: source)

        expect(Faraday).to have_received(:post).with(
          "https://api.openai.com/v1/embeddings",
          { model: "text-embedding-3-small", input: content }.to_json,
          {
            "Authorization" => "Bearer sk-test123",
            "Content-Type" => "application/json"
          }
        )
      end

      it 'works without optional parameters' do
        result = described_class.call(agent: agent, content: content)

        expect(result.success?).to be true
        memory_entry = result.data[:memory_entry]
        expect(memory_entry.source).to be_nil
        expect(memory_entry.metadata).to eq({})
      end

      it 'works with nil metadata' do
        result = described_class.call(agent: agent, content: content, metadata: nil)

        expect(result.success?).to be true
        memory_entry = result.data[:memory_entry]
        expect(memory_entry.metadata).to be_nil
      end

      it 'handles complex metadata structures' do
        complex_metadata = {
          session: { id: "abc123", type: "chat" },
          user: { preferences: ["react", "typescript"] },
          confidence: 0.85
        }

        result = described_class.call(
          agent: agent,
          content: content,
          metadata: complex_metadata
        )

        expect(result.success?).to be true
        memory_entry = result.data[:memory_entry]
        expect(memory_entry.metadata).to eq(complex_metadata.deep_stringify_keys)
      end
    end

    describe 'provider-specific embedding generation' do
      context 'with OpenAI provider' do
        before do
          agent.update(model_provider: "openai")
        end

        it 'uses OpenAI embedding API' do
          described_class.call(agent: agent, content: content)

          expect(Faraday).to have_received(:post).with(
            "https://api.openai.com/v1/embeddings",
            hash_including(model: "text-embedding-3-small"),
            hash_including("Authorization" => "Bearer sk-test123")
          )
        end
      end

      context 'with Anthropic provider' do
        before do
          agent.update(model_provider: "anthropic")
        end

        it 'falls back to OpenAI embedding API' do
          described_class.call(agent: agent, content: content)

          expect(Faraday).to have_received(:post).with(
            "https://api.openai.com/v1/embeddings",
            anything,
            anything
          )
        end
      end

      context 'with Ollama provider' do
        let(:ollama_embedding) { Array.new(1000) { rand } } # Shorter than 1536

        before do
          agent.update(model_provider: "ollama")
          
          # Mock ProviderConfig
          allow(ProviderConfig).to receive(:find_by).with(
            adapter_type: "ollama", enabled: true
          ).and_return(double(base_url: "http://localhost:11434"))

          # Mock Ollama response
          allow(Faraday).to receive(:post).with(
            "http://localhost:11434/api/embeddings",
            anything,
            anything
          ).and_return(
            double(success?: true, body: { embedding: ollama_embedding }.to_json)
          )
        end

        it 'uses Ollama embedding API' do
          described_class.call(agent: agent, content: content)

          expect(Faraday).to have_received(:post).with(
            "http://localhost:11434/api/embeddings",
            { model: "nomic-embed-text", prompt: content }.to_json,
            { "Content-Type" => "application/json" }
          )
        end

        it 'pads short embeddings to 1536 dimensions' do
          result = described_class.call(agent: agent, content: content)

          memory_entry = result.data[:memory_entry]
          expect(memory_entry.embedding.length).to eq(1536)
          # First 1000 should be original, rest should be 0.0
          expect(memory_entry.embedding[999]).to eq(ollama_embedding[999])
          expect(memory_entry.embedding[1000]).to eq(0.0)
          expect(memory_entry.embedding[1535]).to eq(0.0)
        end

        it 'truncates long embeddings to 1536 dimensions' do
          long_embedding = Array.new(2000) { rand }
          allow(Faraday).to receive(:post).with(
            "http://localhost:11434/api/embeddings",
            anything,
            anything
          ).and_return(
            double(success?: true, body: { embedding: long_embedding }.to_json)
          )

          result = described_class.call(agent: agent, content: content)

          memory_entry = result.data[:memory_entry]
          expect(memory_entry.embedding.length).to eq(1536)
          expect(memory_entry.embedding).to eq(long_embedding.take(1536))
        end

        it 'uses default Ollama URL when no provider config found' do
          allow(ProviderConfig).to receive(:find_by).and_return(nil)

          described_class.call(agent: agent, content: content)

          expect(Faraday).to have_received(:post).with(
            "http://localhost:11434/api/embeddings",
            anything,
            anything
          )
        end
      end

      context 'with unknown provider' do
        before do
          agent.update(model_provider: "unknown_provider")
        end

        it 'defaults to OpenAI embedding API' do
          described_class.call(agent: agent, content: content)

          expect(Faraday).to have_received(:post).with(
            "https://api.openai.com/v1/embeddings",
            anything,
            anything
          )
        end
      end

      context 'when agent has no model_provider' do
        before do
          agent.update(model_provider: nil)
        end

        it 'defaults to OpenAI embedding API' do
          described_class.call(agent: agent, content: content)

          expect(Faraday).to have_received(:post).with(
            "https://api.openai.com/v1/embeddings",
            anything,
            anything
          )
        end
      end
    end

    describe 'validation and error handling' do
      context 'with blank content' do
        it 'returns failure for empty string' do
          result = described_class.call(agent: agent, content: "")

          expect(result.success?).to be false
          expect(result.error).to eq("Content cannot be blank")
        end

        it 'returns failure for nil content' do
          result = described_class.call(agent: agent, content: nil)

          expect(result.success?).to be false
          expect(result.error).to eq("Content cannot be blank")
        end

        it 'returns failure for whitespace-only content' do
          result = described_class.call(agent: agent, content: "   \n\t   ")

          expect(result.success?).to be false
          expect(result.error).to eq("Content cannot be blank")
        end
      end

      context 'when embedding generation fails' do
        before do
          allow(Faraday).to receive(:post).and_return(
            double(success?: false, status: 401, body: '{"error": "Invalid API key"}')
          )
        end

        it 'returns failure when embedding cannot be generated' do
          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq("Failed to generate embedding")
        end

        it 'logs error when OpenAI API fails' do
          described_class.call(agent: agent, content: content)

          expect(Rails.logger).to have_received(:error).with(
            'OpenAI embedding failed: {"error": "Invalid API key"}'
          )
        end

        it 'does not create memory entry when embedding fails' do
          expect {
            described_class.call(agent: agent, content: content)
          }.not_to change(MemoryEntry, :count)
        end
      end

      context 'when API key is missing' do
        before do
          allow(VaultEntry).to receive(:find_by).and_return(nil)
        end

        it 'returns failure when API key is not found' do
          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq("Failed to generate embedding")
        end
      end

      context 'when HTTP request raises exception' do
        before do
          allow(Faraday).to receive(:post).and_raise(StandardError, "Network timeout")
        end

        it 'handles network errors gracefully' do
          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq("Memory storage failed: Network timeout")
        end

        it 'logs embedding error' do
          described_class.call(agent: agent, content: content)

          expect(Rails.logger).to have_received(:error).with(
            "OpenAI embedding error: Network timeout"
          )
        end
      end

      context 'when MemoryEntry creation fails' do
        before do
          allow(MemoryEntry).to receive(:create).and_return(
            double(
              persisted?: false,
              errors: double(full_messages: ["Agent can't be blank", "Content is too long"])
            )
          )
        end

        it 'returns failure with validation errors' do
          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq(["Agent can't be blank", "Content is too long"])
        end
      end

      context 'when MemoryEntry.create raises exception' do
        before do
          allow(MemoryEntry).to receive(:create).and_raise(ActiveRecord::RecordInvalid, "Database constraint violation")
        end

        it 'returns failure with exception message' do
          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq("Memory storage failed: Database constraint violation")
        end
      end
    end

    describe 'embedding API error handling' do
      context 'with OpenAI API errors' do
        it 'handles JSON parsing errors' do
          allow(Faraday).to receive(:post).and_return(
            double(success?: true, body: "invalid json")
          )

          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq("Memory storage failed: unexpected token at 'invalid json'")
          expect(Rails.logger).to have_received(:error).with(
            /OpenAI embedding error:.*JSON/
          )
        end

        it 'handles missing embedding data in response' do
          allow(Faraday).to receive(:post).and_return(
            double(success?: true, body: '{"data": [{}]}')
          )

          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq("Failed to generate embedding")
        end
      end

      context 'with Ollama API errors' do
        before do
          agent.update(model_provider: "ollama")
          allow(ProviderConfig).to receive(:find_by).and_return(
            double(base_url: "http://localhost:11434")
          )
        end

        it 'handles Ollama API failures' do
          allow(Faraday).to receive(:post).and_return(
            double(success?: false, body: '{"error": "Model not found"}')
          )

          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq("Failed to generate embedding")
          expect(Rails.logger).to have_received(:error).with(
            'Ollama embedding failed: {"error": "Model not found"}'
          )
        end

        it 'handles missing embedding field in Ollama response' do
          allow(Faraday).to receive(:post).and_return(
            double(success?: true, body: '{"model": "nomic-embed-text"}')
          )

          result = described_class.call(agent: agent, content: content)

          expect(result.success?).to be false
          expect(result.error).to eq("Memory storage failed: undefined method `length' for nil:NilClass")
        end
      end
    end

    describe 'edge cases' do
      context 'with very long content' do
        let(:long_content) { "word " * 10000 } # Very long content

        it 'handles very long content' do
          result = described_class.call(agent: agent, content: long_content)

          expect(result.success?).to be true
          memory_entry = result.data[:memory_entry]
          expect(memory_entry.content).to eq(long_content)
        end
      end

      context 'with special characters in content' do
        let(:special_content) { "Content with émojis 🚀 and spëcial chars: <>&\"'" }

        it 'handles special characters correctly' do
          result = described_class.call(agent: agent, content: special_content)

          expect(result.success?).to be true
          memory_entry = result.data[:memory_entry]
          expect(memory_entry.content).to eq(special_content)
        end
      end

      context 'with very large metadata' do
        let(:large_metadata) do
          {
            large_array: Array.new(1000) { |i| "item_#{i}" },
            large_hash: Hash[Array.new(100) { |i| ["key_#{i}", "value_#{i}"] }]
          }
        end

        it 'handles large metadata structures' do
          result = described_class.call(
            agent: agent,
            content: content,
            metadata: large_metadata
          )

          expect(result.success?).to be true
          memory_entry = result.data[:memory_entry]
          expect(memory_entry.metadata["large_array"].length).to eq(1000)
          expect(memory_entry.metadata["large_hash"].length).to eq(100)
        end
      end
    end

    describe 'embedding dimension consistency' do
      it 'always stores embeddings with 1536 dimensions for OpenAI' do
        result = described_class.call(agent: agent, content: content)

        memory_entry = result.data[:memory_entry]
        expect(memory_entry.embedding.length).to eq(1536)
      end

      it 'pads Ollama embeddings to 1536 dimensions' do
        agent.update(model_provider: "ollama")
        short_embedding = Array.new(500) { rand }
        
        allow(ProviderConfig).to receive(:find_by).and_return(
          double(base_url: "http://localhost:11434")
        )
        allow(Faraday).to receive(:post).and_return(
          double(success?: true, body: { embedding: short_embedding }.to_json)
        )

        result = described_class.call(agent: agent, content: content)

        memory_entry = result.data[:memory_entry]
        expect(memory_entry.embedding.length).to eq(1536)
        expect(memory_entry.embedding[499]).to eq(short_embedding[499])
        expect(memory_entry.embedding[500]).to eq(0.0)
      end
    end
  end
end