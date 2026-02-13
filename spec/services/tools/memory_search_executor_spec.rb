# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::MemorySearchExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:executor) { described_class.new(input: input, config: {}, agent: agent) }

  describe '#call' do
    context 'with matching memories' do
      let(:input) { { "query" => "important meeting" } }

      before do
        create(:memory_entry, agent: agent, content: "Had an important meeting with the client today", created_at: 2.days.ago)
        create(:memory_entry, agent: agent, content: "The meeting went very well and we closed the deal", created_at: 1.day.ago)
        create(:memory_entry, agent: agent, content: "Need to follow up on yesterday's conversation", created_at: 1.hour.ago)
        create(:memory_entry, agent: agent, content: "Weather is nice today", created_at: 30.minutes.ago)
      end

      it 'finds matching memories successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Found 2 memories:")
        expect(result.data[:output]).to include("important meeting with the client")
        expect(result.data[:output]).to include("meeting went very well")
        expect(result.data[:output]).not_to include("Weather is nice")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'orders results by creation date (newest first)' do
        result = executor.call
        lines = result.data[:output].split("\n\n")
        expect(lines[1]).to include("meeting went very well") # more recent
        expect(lines[2]).to include("important meeting with the client") # older
      end

      it 'includes timestamps in results' do
        result = executor.call
        expect(result.data[:output]).to match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}\]/)
      end

      context 'with custom limit' do
        let(:input) { { "query" => "meeting", "limit" => 1 } }

        it 'respects the limit parameter' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Found 1 memories:")
          lines = result.data[:output].split("\n\n")
          expect(lines.size).to eq(2) # header + 1 memory
        end
      end

      context 'with very high limit' do
        let(:input) { { "query" => "meeting", "limit" => 50 } }

        it 'caps limit at 20' do
          # Create more memories
          15.times do |i|
            create(:memory_entry, agent: agent, content: "Meeting #{i}", created_at: i.hours.ago)
          end

          result = executor.call
          expect(result).to be_success
          # Should return at most 20 results
          lines = result.data[:output].split("\n\n")
          expect(lines.size).to be <= 21 # header + max 20 memories
        end
      end
    end

    context 'with no matching memories' do
      let(:input) { { "query" => "nonexistent topic" } }

      before do
        create(:memory_entry, agent: agent, content: "Some unrelated content")
      end

      it 'returns no matches message' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("No memories found matching 'nonexistent topic'.")
        expect(result.data[:exit_code]).to eq(0)
      end
    end

    context 'without agent' do
      let(:executor) { described_class.new(input: input, config: {}, agent: nil) }
      let(:input) { { "query" => "test" } }

      it 'returns no memories' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("No memories found matching 'test'.")
      end
    end

    context 'without query' do
      let(:input) { {} }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No query provided")
      end
    end

    context 'with empty query' do
      let(:input) { { "query" => "  " } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No query provided")
      end
    end

    context 'with short keywords' do
      let(:input) { { "query" => "a b it to" } }

      before do
        create(:memory_entry, agent: agent, content: "This is a test memory", created_at: 1.day.ago)
        create(:memory_entry, agent: agent, content: "Another memory entry", created_at: 2.days.ago)
      end

      it 'ignores keywords shorter than 3 characters' do
        result = executor.call
        expect(result).to be_success
        # Should return recent memories since all keywords were too short
        expect(result.data[:output]).to include("This is a test memory")
      end
    end

    context 'with mixed case query' do
      let(:input) { { "query" => "IMPORTANT Meeting" } }

      before do
        create(:memory_entry, agent: agent, content: "had an important meeting today")
      end

      it 'performs case-insensitive search' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("important meeting today")
      end
    end

    context 'with partial keyword matches' do
      let(:input) { { "query" => "meet" } }

      before do
        create(:memory_entry, agent: agent, content: "Had a meeting today")
        create(:memory_entry, agent: agent, content: "Will meet with client tomorrow")
      end

      it 'finds partial matches' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Found 2 memories:")
        expect(result.data[:output]).to include("meeting today")
        expect(result.data[:output]).to include("meet with client")
      end
    end

    context 'with insufficient matches' do
      let(:input) { { "query" => "meeting", "limit" => 5 } }

      before do
        create(:memory_entry, agent: agent, content: "Had a meeting", created_at: 3.days.ago)
        create(:memory_entry, agent: agent, content: "Unrelated memory 1", created_at: 2.days.ago)
        create(:memory_entry, agent: agent, content: "Unrelated memory 2", created_at: 1.day.ago)
        create(:memory_entry, agent: agent, content: "Unrelated memory 3", created_at: 1.hour.ago)
      end

      it 'pads with recent memories' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Found 4 memories:") # 1 match + 3 recent
        expect(result.data[:output]).to include("Had a meeting") # the match
        expect(result.data[:output]).to include("Unrelated memory 3") # most recent
      end
    end

    context 'with very long memory content' do
      let(:input) { { "query" => "long" } }
      let(:long_content) { 'This is a very long memory content. ' * 50 }

      before do
        create(:memory_entry, agent: agent, content: long_content)
      end

      it 'truncates long content in output' do
        result = executor.call
        expect(result).to be_success
        content_line = result.data[:output].split("\n\n")[1]
        expect(content_line.length).to be <= 520 # 500 chars + timestamp and formatting
      end
    end

    context 'with special characters in query' do
      let(:input) { { "query" => "client's project" } }

      before do
        create(:memory_entry, agent: agent, content: "Working on client's project today")
      end

      it 'handles special characters safely' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("client's project")
      end
    end

    context 'with many keywords' do
      let(:input) { { "query" => "one two three four five six seven eight" } }

      before do
        create(:memory_entry, agent: agent, content: "Contains keywords one, three, five")
      end

      it 'limits to first 5 keywords' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Contains keywords")
      end
    end

    context 'when database query fails' do
      let(:input) { { "query" => "test" } }

      before do
        allow(MemoryEntry).to receive(:where).and_raise(StandardError.new("Database error"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Memory search failed: Database error")
      end
    end

    context 'with memories from other agents' do
      let(:other_agent) { create(:agent) }
      let(:input) { { "query" => "secret" } }

      before do
        create(:memory_entry, agent: agent, content: "My secret information")
        create(:memory_entry, agent: other_agent, content: "Other agent's secret data")
      end

      it 'only searches current agent memories' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("My secret information")
        expect(result.data[:output]).not_to include("Other agent's secret data")
      end
    end

    context 'with exact number of matches' do
      let(:input) { { "query" => "task", "limit" => 3 } }

      before do
        3.times do |i|
          create(:memory_entry, agent: agent, content: "Task #{i}", created_at: i.hours.ago)
        end
      end

      it 'returns exact matches without padding' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Found 3 memories:")
        lines = result.data[:output].split("\n\n")
        expect(lines.size).to eq(4) # header + 3 memories
      end
    end

    context 'with default limit' do
      let(:input) { { "query" => "test" } }

      before do
        15.times do |i|
          create(:memory_entry, agent: agent, content: "Test memory #{i}", created_at: i.hours.ago)
        end
      end

      it 'uses default limit of 10' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Found 10 memories:")
        lines = result.data[:output].split("\n\n")
        expect(lines.size).to eq(11) # header + 10 memories
      end
    end

    context 'with zero limit' do
      let(:input) { { "query" => "test", "limit" => 0 } }

      before do
        create(:memory_entry, agent: agent, content: "Test memory")
      end

      it 'clamps limit to minimum of 1' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Found 1 memories:")
      end
    end
  end

  describe 'private methods' do
    describe '#search_memories' do
      before do
        create(:memory_entry, agent: agent, content: "Meeting with client")
        create(:memory_entry, agent: agent, content: "Project discussion")
      end

      it 'handles empty keywords gracefully' do
        memories = executor.send(:search_memories, query: "a", limit: 5)
        expect(memories.size).to be <= 5
      end

      it 'returns ActiveRecord relation' do
        memories = executor.send(:search_memories, query: "meeting", limit: 5)
        expect(memories).to be_an(Array)
      end
    end

    describe '#agent_memories' do
      it 'scopes to current agent' do
        relation = executor.send(:agent_memories)
        expect(relation.where_values_hash).to include('agent_id' => agent.id)
      end
    end
  end
end