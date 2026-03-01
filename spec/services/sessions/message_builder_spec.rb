# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::MessageBuilder do
  let(:agent) { create(:agent, model_provider: "anthropic", llm_model: "claude-3-5-sonnet") }
  let(:session) { create(:session, agent: agent, transcript: transcript) }
  let(:transcript) { [] }

  before do
    allow(Memory::ContextBuilder).to receive(:call).and_return({ context: nil, entries: [] })
  end

  describe ".call" do
    subject(:result) { described_class.call(session: session, agent: agent) }

    context "with empty transcript" do
      it "returns success with system message only" do
        expect(result.success?).to be true
        messages = result.data[:messages]
        expect(messages.size).to eq(1)
        expect(messages.first[:role]).to eq("system")
      end
    end

    context "with transcript messages" do
      let(:transcript) do
        [
          { "role" => "user", "content" => "Hello", "timestamp" => 1.hour.ago.iso8601 },
          { "role" => "assistant", "content" => "Hi there!", "timestamp" => 1.hour.ago.iso8601 },
          { "role" => "user", "content" => "How are you?", "timestamp" => 30.minutes.ago.iso8601 },
          { "role" => "assistant", "content" => "I'm great!", "timestamp" => 30.minutes.ago.iso8601 }
        ]
      end

      it "includes system prompt and last RAW_MESSAGES_TO_KEEP messages" do
        messages = result.data[:messages]
        # 1 system + 4 transcript (all 4 kept since RAW_MESSAGES_TO_KEEP = 4)
        expect(messages.size).to eq(5)
        expect(messages.first[:role]).to eq("system")
        expect(messages[1][:role]).to eq("user")
        expect(messages[1][:content]).to eq("Hello")
      end
    end

    context "with more messages than RAW_MESSAGES_TO_KEEP" do
      let(:transcript) do
        6.times.map do |i|
          role = i.even? ? "user" : "assistant"
          { "role" => role, "content" => "Message #{i}", "timestamp" => (6 - i).minutes.ago.iso8601 }
        end
      end

      it "only includes the last 4 messages" do
        messages = result.data[:messages]
        # 1 system + 4 transcript
        expect(messages.size).to eq(5)
        expect(messages[1][:content]).to eq("Message 2")
        expect(messages.last[:content]).to eq("Message 5")
      end
    end

    context "with memory context" do
      before do
        allow(Memory::ContextBuilder).to receive(:call).and_return({
          context: "## Your Memories\n- User likes Ruby",
          entries: []
        })
      end

      let(:transcript) do
        [{ "role" => "user", "content" => "Tell me about Ruby", "timestamp" => Time.current.iso8601 }]
      end

      it "includes memory context in system prompt" do
        messages = result.data[:messages]
        system_blocks = messages.first[:content]
        dynamic_block = system_blocks.find { |b| b[:text]&.include?("Your Memories") }
        expect(dynamic_block).to be_present
      end
    end

    context "with mood override" do
      let(:session) { create(:session, agent: agent, transcript: [], metadata: { "mood" => "casual and friendly" }) }

      it "includes mood in system prompt" do
        messages = result.data[:messages]
        system_blocks = messages.first[:content]
        mood_text = system_blocks.map { |b| b[:text] }.join
        expect(mood_text).to include("casual and friendly")
      end
    end

    context "with prompt addons" do
      let(:transcript) { [{ "role" => "user", "content" => "Hello", "timestamp" => Time.current.iso8601 }] }

      subject(:result) do
        described_class.call(session: session, agent: agent, prompt_addons: ["Extra context here"])
      end

      it "includes addons in system prompt" do
        messages = result.data[:messages]
        system_blocks = messages.first[:content]
        addon_text = system_blocks.map { |b| b[:text] }.join
        expect(addon_text).to include("Extra context here")
      end
    end

    context "with conversation summary" do
      let(:session) do
        create(:session, agent: agent, transcript: [], conversation_summary: "User discussed Rails refactoring")
      end

      it "includes summary in system prompt" do
        messages = result.data[:messages]
        system_blocks = messages.first[:content]
        summary_text = system_blocks.map { |b| b[:text] }.join
        expect(summary_text).to include("User discussed Rails refactoring")
      end
    end

    context "with image attachments on current message" do
      let(:attachment) do
        att = create(:chat_attachment, session: session, content_type: "image/png", filename: "photo.png")
        allow(att).to receive(:image?).and_return(true)
        allow(att).to receive(:file).and_return(double(attached?: true))
        allow(att).to receive(:to_base64).and_return("base64data")
        allow(att).to receive(:media_type).and_return("image/png")
        att
      end

      let(:transcript) do
        [
          { "role" => "user", "content" => "What is this?", "images" => [{ "attachment_id" => 1 }], "timestamp" => Time.current.iso8601 }
        ]
      end

      subject(:result) do
        described_class.call(session: session, agent: agent, current_images: [attachment])
      end

      it "builds a vision message with image blocks" do
        messages = result.data[:messages]
        user_msg = messages.last
        expect(user_msg[:role]).to eq("user")
        expect(user_msg[:content]).to be_an(Array)
        image_block = user_msg[:content].find { |b| b[:type] == "image" }
        expect(image_block).to be_present
        expect(image_block[:source][:data]).to eq("base64data")
      end
    end

    context "with past image references (not current)" do
      let(:transcript) do
        [
          { "role" => "user", "content" => "Look at this", "images" => [{ "attachment_id" => 1 }], "timestamp" => 5.minutes.ago.iso8601 },
          { "role" => "assistant", "content" => "Nice image!", "timestamp" => 4.minutes.ago.iso8601 },
          { "role" => "user", "content" => "What else?", "timestamp" => Time.current.iso8601 },
          { "role" => "assistant", "content" => "Nothing else", "timestamp" => Time.current.iso8601 }
        ]
      end

      it "uses text-only message with image count note" do
        messages = result.data[:messages]
        first_user = messages[1]
        expect(first_user[:content]).to include("[User attached 1 image(s)]")
        expect(first_user[:content]).not_to be_an(Array)
      end
    end

    context "when memory recall fails" do
      before do
        allow(Memory::ContextBuilder).to receive(:call).and_raise(StandardError, "Embedding service down")
      end

      let(:transcript) do
        [{ "role" => "user", "content" => "Tell me something", "timestamp" => Time.current.iso8601 }]
      end

      it "still returns success without memory context" do
        expect(result.success?).to be true
        messages = result.data[:messages]
        expect(messages.size).to eq(2)
      end
    end
  end
end
