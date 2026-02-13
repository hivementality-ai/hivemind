# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::SessionsHistoryExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  describe '#call' do
    context 'with valid session' do
      let(:session) { create(:session, session_key: 'test-session-123', title: 'Test Session') }
      let(:input) { { "session_key" => "test-session-123" } }

      before do
        session.update(transcript: [
          { "role" => "user", "content" => "Hello, how are you?" },
          { "role" => "assistant", "content" => "I'm doing well, thank you! How can I help you today?" },
          { "role" => "user", "content" => "Can you help me with a programming problem?" },
          { "role" => "assistant", "content" => "Of course! I'd be happy to help with programming. What specific problem are you working on?" },
          { "role" => "user", "content" => "I need to write a function to sort an array" }
        ])
      end

      it 'returns session history successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Session: Test Session (5 total messages)")
        expect(result.data[:output]).to include("Last 5:")
        expect(result.data[:output]).to include("[user] Hello, how are you?")
        expect(result.data[:output]).to include("[assistant] I'm doing well, thank you!")
        expect(result.data[:output]).to include("[user] I need to write a function to sort an array")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'with custom limit' do
        let(:input) { { "session_key" => "test-session-123", "limit" => 3 } }

        it 'respects the limit parameter' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Last 3:")
          
          # Should only include the last 3 messages
          expect(result.data[:output]).to include("Can you help me with a programming problem?")
          expect(result.data[:output]).to include("Of course! I'd be happy to help")
          expect(result.data[:output]).to include("I need to write a function to sort an array")
          
          # Should not include the first messages
          expect(result.data[:output]).not_to include("Hello, how are you?")
        end
      end

      context 'with limit larger than message count' do
        let(:input) { { "session_key" => "test-session-123", "limit" => 10 } }

        it 'returns all available messages' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Last 5:") # actual count
          expect(result.data[:output]).to include("[user] Hello, how are you?") # first message included
        end
      end

      context 'with very high limit' do
        let(:input) { { "session_key" => "test-session-123", "limit" => 100 } }

        it 'caps limit at 50' do
          # Create more messages to test the cap
          transcript = (1..60).map do |i|
            { "role" => "user", "content" => "Message #{i}" }
          end
          session.update(transcript: transcript)

          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Last 50:")
          
          # Count the number of message blocks (separated by \n\n)
          message_blocks = result.data[:output].split("\n\n").select { |block| block.include?("[user]") }
          expect(message_blocks.size).to eq(50)
        end
      end

      context 'with zero limit' do
        let(:input) { { "session_key" => "test-session-123", "limit" => 0 } }

        it 'clamps limit to minimum of 1' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Last 1:")
          expect(result.data[:output]).to include("I need to write a function to sort an array")
        end
      end
    end

    context 'with session having no title' do
      let(:session) { create(:session, session_key: 'untitled-session', title: nil) }
      let(:input) { { "session_key" => "untitled-session" } }

      before do
        session.update(transcript: [
          { "role" => "user", "content" => "Test message" }
        ])
      end

      it 'uses session_key when title is nil' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Session: untitled-session (1 total messages)")
      end
    end

    context 'with session having empty title' do
      let(:session) { create(:session, session_key: 'empty-title-session', title: '') }
      let(:input) { { "session_key" => "empty-title-session" } }

      before do
        session.update(transcript: [
          { "role" => "user", "content" => "Test message" }
        ])
      end

      it 'uses session_key when title is empty' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Session: empty-title-session (1 total messages)")
      end
    end

    context 'with empty session (no transcript)' do
      let(:session) { create(:session, session_key: 'empty-session', transcript: nil) }
      let(:input) { { "session_key" => "empty-session" } }

      it 'handles nil transcript gracefully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Session has no messages.")
        expect(result.data[:exit_code]).to eq(0)
      end
    end

    context 'with empty transcript array' do
      let(:session) { create(:session, session_key: 'empty-array-session', transcript: []) }
      let(:input) { { "session_key" => "empty-array-session" } }

      it 'handles empty transcript array' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Session has no messages.")
        expect(result.data[:exit_code]).to eq(0)
      end
    end

    context 'with messages having missing fields' do
      let(:session) { create(:session, session_key: 'malformed-session') }
      let(:input) { { "session_key" => "malformed-session" } }

      before do
        session.update(transcript: [
          { "role" => "user", "content" => "Normal message" },
          { "content" => "Message without role" },
          { "role" => "assistant" },  # Message without content
          {}  # Empty message
        ])
      end

      it 'handles malformed messages gracefully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("[user] Normal message")
        expect(result.data[:output]).to include("[unknown] Message without role")
        expect(result.data[:output]).to include("[assistant] ")
        expect(result.data[:output]).to include("[unknown] ")
      end
    end

    context 'with very long messages' do
      let(:session) { create(:session, session_key: 'long-message-session') }
      let(:input) { { "session_key" => "long-message-session" } }
      let(:long_message) { 'This is a very long message. ' * 50 }

      before do
        session.update(transcript: [
          { "role" => "user", "content" => long_message },
          { "role" => "assistant", "content" => "Short response" }
        ])
      end

      it 'truncates long messages to 500 characters' do
        result = executor.call
        expect(result).to be_success
        
        user_message_line = result.data[:output].lines.find { |line| line.include?("[user]") }
        expect(user_message_line.length).to be <= 510  # [user] + space + 500 chars + some margin
        expect(result.data[:output]).to include("[assistant] Short response")
      end
    end

    context 'without session_key' do
      let(:input) { {} }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No session_key provided")
      end
    end

    context 'with empty session_key' do
      let(:input) { { "session_key" => "  " } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No session_key provided")
      end
    end

    context 'with non-existent session' do
      let(:input) { { "session_key" => "nonexistent-session" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Session not found: nonexistent-session")
      end
    end

    context 'with default limit' do
      let(:session) { create(:session, session_key: 'default-limit-session') }
      let(:input) { { "session_key" => "default-limit-session" } }

      before do
        # Create 25 messages
        transcript = (1..25).map do |i|
          { "role" => "user", "content" => "Message #{i}" }
        end
        session.update(transcript: transcript)
      end

      it 'uses default limit of 20' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Last 20:")
        
        # Should include messages 6-25 (last 20 out of 25)
        expect(result.data[:output]).to include("Message 25")
        expect(result.data[:output]).to include("Message 6")
        expect(result.data[:output]).not_to include("Message 5")
      end
    end

    context 'when database query fails' do
      let(:input) { { "session_key" => "test-session" } }

      before do
        allow(Session).to receive(:find_by).and_raise(StandardError.new("Database connection lost"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Sessions history failed: Database connection lost")
      end
    end

    context 'with different message roles' do
      let(:session) { create(:session, session_key: 'multi-role-session') }
      let(:input) { { "session_key" => "multi-role-session" } }

      before do
        session.update(transcript: [
          { "role" => "system", "content" => "System initialization message" },
          { "role" => "user", "content" => "User question" },
          { "role" => "assistant", "content" => "Assistant response" },
          { "role" => "tool", "content" => "Tool execution result" }
        ])
      end

      it 'displays all role types correctly' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("[system] System initialization message")
        expect(result.data[:output]).to include("[user] User question")
        expect(result.data[:output]).to include("[assistant] Assistant response")
        expect(result.data[:output]).to include("[tool] Tool execution result")
      end
    end

    context 'with messages containing newlines' do
      let(:session) { create(:session, session_key: 'multiline-session') }
      let(:input) { { "session_key" => "multiline-session" } }

      before do
        session.update(transcript: [
          { "role" => "user", "content" => "First line\nSecond line\nThird line" },
          { "role" => "assistant", "content" => "Response with\nmultiple lines" }
        ])
      end

      it 'preserves message formatting' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("First line\nSecond line\nThird line")
        expect(result.data[:output]).to include("Response with\nmultiple lines")
      end
    end

    context 'with transcript containing non-hash elements' do
      let(:session) { create(:session, session_key: 'invalid-transcript-session') }
      let(:input) { { "session_key" => "invalid-transcript-session" } }

      before do
        # Simulate corrupted transcript with mixed types
        session.update_column(:transcript, [
          { "role" => "user", "content" => "Valid message" },
          "invalid string message",
          { "role" => "assistant", "content" => "Another valid message" }
        ])
      end

      it 'handles invalid transcript elements gracefully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("[user] Valid message")
        expect(result.data[:output]).to include("[assistant] Another valid message")
        
        # The string element should be handled (will call [] on string which returns nil)
        lines = result.data[:output].split("\n\n").select { |line| line.start_with?("[") }
        expect(lines.size).to eq(3) # Should process all 3 elements
      end
    end
  end
end