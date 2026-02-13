# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Memory::Search do
  describe '.call' do
    let(:agent) { create(:agent, model_provider: "openai") }
    let(:query) { "How do I deploy to production?" }
    let(:sample_embedding) { Array.new(1536) { rand } }

    # Mock memory entries
    let!(:memory_entry_1) do
      create(:memory_entry,
             agent: agent,
             content: "Production deployment requires running docker-compose up",
             source_type: "conversation",
             source_id: "123",
             metadata: { session_id: "abc" })
    end
    
    let!(:memory_entry_2) do
      create(:memory_entry,
             agent: agent,
             content: "Use CI/CD pipeline for automated deployments",
             source_type: "note",
             source_id: "456",
             metadata: { tags: ["deployment", "ci-cd"] })
    end

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

      # Mock MemoryEntry search
      allow(MemoryEntry).to receive(:search_with_threshold).and_return([
        double(
          id: memory_entry_1.id,
          content: memory_entry_1.content,
          neighbor_distance: 0.1, # High similarity
          source_type: memory_entry_1.source_type,
          source_id: memory_entry_1.source_id,
          metadata: memory_entry_1.metadata,
          created_at: memory_entry_1.created_at
        ),
        double(
          id: memory_entry_2.id,
          content: memory_entry_2.content,
          neighbor_distance: 0.3, # Lower similarity
          source_type: memory_entry_2.source_type,
          source_id: memory_entry_2.source_id,
          metadata: memory_entry_2.metadata,
          created_at: memory_entry_2.created_at
        )
      ])
    end

    describe 'successful search' do
      it 'performs memory search and returns enriched results' do
        result = described_class.call(agent: agent, query: query)

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        
        data = result.data
        expect(data[:query]).to eq(query)
        expect(data[:results]).to be_an(Array)
        expect(data[:count]).to eq(2)
      end

      it 'generates query embedding using OpenAI' do
        described_class.call(agent: agent, query: query)

        expect(Faraday).to have_received(:post).with(
          "https://api.openai.com/v1/embeddings",
          { model: "text-embedding-3-small", input: query }.to_json,
          {
            "Authorization" => "Bearer sk-test123",
            "Content-Type" => "application/json"
          }
        )
      end

      it 'searches memory entries with correct parameters' do
        described_class.call(agent: agent, query: query, limit: 5, threshold: 0.8)

        expect(MemoryEntry).to have_received(:search_with_threshold).with(
          embedding: sample_embedding,
          agent: agent,
          threshold: 0.8,
          limit: 5
        )
      end

      it 'enriches results with similarity scores' do
        result = described_class.call(agent: agent, query: query)

        results = result.data[:results]
        first_result = results.first
        
        expect(first_result).to include(
          id: memory_entry_1.id,
          content: memory_entry_1.content,
          similarity: 0.9, # 1 - 0.1
          source_type: "conversation",
          source_id: "123",
          metadata: { "session_id" => "abc" },
          created_at: memory_entry_1.created_at
        )

        second_result = results.last
        expect(second_result[:similarity]).to eq(0.7) # 1 - 0.3
      end

      it 'uses default parameters when not specified' do
        described_class.call(agent: agent, query: query)

        expect(MemoryEntry).to have_received(:search_with_threshold).with(
          embedding: sample_embedding,
          agent: agent,
          threshold: 0.7, # default
          limit: 10 # default
        )
      end
    end

    describe 'provider-specific embedding generation' do
      context 'with OpenAI provider' do
        before do
          agent.update(model_provider: "openai")
        end

        it 'uses OpenAI embedding API' do
          described_class.call(agent: agent, query: query)

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
          described_class.call(agent: agent, query: query)

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

          # Update MemoryEntry mock to expect padded embedding
          allow(MemoryEntry).to receive(:search_with_threshold).and_return([])
        end

        it 'uses Ollama embedding API' do
          described_class.call(agent: agent, query: query)

          expect(Faraday).to have_received(:post).with(
            "http://localhost:11434/api/embeddings",
            { model: "nomic-embed-text", prompt: query }.to_json,
            { "Content-Type" => "application/json" }
          )
        end

        it 'pads short embeddings to 1536 dimensions' do
          described_class.call(agent: agent, query: query)

          # The search should be called with a 1536-dimensional vector
          expect(MemoryEntry).to have_received(:search_with_threshold) do |args|
            expect(args[:embedding].length).to eq(1536)
          end
        end
      end

      context 'with unknown provider' do
        before do
          agent.update(model_provider: "unknown")
        end

        it 'defaults to OpenAI embedding API' do
          described_class.call(agent: agent, query: query)

          expect(Faraday).to have_received(:post).with(
            "https://api.openai.com/v1/embeddings",
            anything,
            anything
          )
        end
      end
    end

    describe 'validation and error handling' do
      context 'with blank query' do
        it 'returns failure for empty string' do
          result = described_class.call(agent: agent, query: "")

          expect(result.success?).to be false
          expect(result.error).to eq("Query cannot be blank")
        end

        it 'returns failure for nil query' do
          result = described_class.call(agent: agent, query: nil)

          expect(result.success?).to be false
          expect(result.error).to eq("Query cannot be blank")
        end

        it 'returns failure for whitespace-only query' do
          result = described_class.call(agent: agent, query: "   ")

          expect(result.success?).to be false
          expect(result.error).to eq("Query cannot be blank")
        end
      end

      context 'when embedding generation fails' do
        before do
          allow(Faraday).to receive(:post).and_return(
            double(success?: false, status: 401)
          )
        end

        it 'returns failure when embedding cannot be generated' do
          result = described_class.call(agent: agent, query: query)

          expect(result.success?).to be false
          expect(result.error).to eq("Failed to generate query embedding")
        end

        it 'does not perform memory search when embedding fails' do
          described_class.call(agent: agent, query: query)

          expect(MemoryEntry).not_to have_received(:search_with_threshold)
        end
      end

      context 'when API key is missing' do
        before do
          allow(VaultEntry).to receive(:find_by).and_return(nil)
        end

        it 'returns failure when API key is not found' do
          result = described_class.call(agent: agent, query: query)

          expect(result.success?).to be false
          expect(result.error).to eq("Failed to generate query embedding")
        end
      end

      context 'when HTTP request raises exception' do
        before do
          allow(Faraday).to receive(:post).and_raise(StandardError, "Network error")
        end

        it 'handles network errors gracefully' do
          result = described_class.call(agent: agent, query: query)

          expect(result.success?).to be false
          expect(result.error).to eq("Memory search failed: Network error")
        end
      end

      context 'when MemoryEntry search raises exception' do
        before do
          allow(MemoryEntry).to receive(:search_with_threshold).and_raise(
            StandardError, "Vector database error"
          )
        end

        it 'handles search errors gracefully' do
          result = described_class.call(agent: agent, query: query)

          expect(result.success?).to be false
          expect(result.error).to eq("Memory search failed: Vector database error")
        end
      end
    end

    describe 'edge cases' do
      context 'when no results found' do
        before do
          allow(MemoryEntry).to receive(:search_with_threshold).and_return([])
        end

        it 'returns empty results successfully' do
          result = described_class.call(agent: agent, query: query)

          expect(result.success?).to be true
          expect(result.data[:results]).to eq([])
          expect(result.data[:count]).to eq(0)
        end
      end

      context 'with very high threshold' do
        it 'accepts high threshold values' do
          result = described_class.call(agent: agent, query: query, threshold: 0.99)

          expect(result.success?).to be true
          expect(MemoryEntry).to have_received(:search_with_threshold).with(
            hash_including(threshold: 0.99)
          )
        end
      end

      context 'with very large limit' do
        it 'accepts large limit values' do
          result = described_class.call(agent: agent, query: query, limit: 1000)

          expect(result.success?).to be true
          expect(MemoryEntry).to have_received(:search_with_threshold).with(
            hash_including(limit: 1000)
          )
        end
      end
    end

    describe 'similarity score calculation' do
      it 'converts neighbor distance to similarity score correctly' do
        # neighbor_distance of 0.1 should become similarity of 0.9
        # neighbor_distance of 0.3 should become similarity of 0.7
        result = described_class.call(agent: agent, query: query)

        results = result.data[:results]
        expect(results[0][:similarity]).to eq(0.9)
        expect(results[1][:similarity]).to eq(0.7)
      end

      it 'rounds similarity scores to 4 decimal places' do
        # Mock a result with more precision
        allow(MemoryEntry).to receive(:search_with_threshold).and_return([
          double(
            id: 1,
            content: "test",
            neighbor_distance: 0.12345678, # Should become similarity 0.8765
            source_type: "test",
            source_id: "1",
            metadata: {},
            created_at: Time.current
          )
        ])

        result = described_class.call(agent: agent, query: query)
        similarity = result.data[:results].first[:similarity]

        expect(similarity).to eq(0.8765)
      end
    end
  end
end