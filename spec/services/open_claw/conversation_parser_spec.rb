# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::ConversationParser do
  let(:agent) { create(:agent) }

  after { cleanup_openclaw_workspace(@workspace_path) if @workspace_path }

  describe ".call" do
    context "with array-format conversations" do
      before do
        @workspace_path = create_openclaw_workspace(
          conversations: {
            "chat1.json" => [
              { "role" => "user", "content" => "Hello!", "timestamp" => "2024-01-15T10:00:00Z" },
              { "role" => "assistant", "content" => "Hi there!", "timestamp" => "2024-01-15T10:00:01Z" }
            ]
          }
        )
      end

      it "creates archived sessions" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:count]).to eq(1)

        session = Session.find_by(agent: agent, status: :archived)
        expect(session).to be_present
        expect(session.transcript.size).to eq(2)
        expect(session.title).to include("chat1")
      end
    end

    context "with wrapped-format conversations" do
      before do
        @workspace_path = create_openclaw_workspace(
          conversations: {
            "chat2.json" => { "messages" => [
              { "role" => "user", "content" => "How are you?" },
              { "role" => "assistant", "content" => "I'm great!" }
            ] }
          }
        )
      end

      it "normalizes wrapped format" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:count]).to eq(1)

        session = Session.last
        expect(session.transcript.size).to eq(2)
      end
    end

    context "with multiple conversations" do
      before do
        @workspace_path = create_openclaw_workspace(
          conversations: {
            "chat1.json" => [{ "role" => "user", "content" => "First chat" }],
            "chat2.json" => [{ "role" => "user", "content" => "Second chat" }]
          }
        )
      end

      it "imports all conversations" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:count]).to eq(2)
        expect(result.data[:files]).to contain_exactly("chat1.json", "chat2.json")
      end
    end

    context "idempotent re-run" do
      before do
        @workspace_path = create_openclaw_workspace(
          conversations: {
            "chat1.json" => [{ "role" => "user", "content" => "Hello" }]
          }
        )
      end

      it "does not create duplicate sessions" do
        described_class.call(workspace_path: @workspace_path, agent: agent)
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(Session.where(agent: agent).count).to eq(1)
      end
    end

    context "without conversations directory" do
      before do
        @workspace_path = create_openclaw_workspace(conversations: {})
      end

      it "returns zero count" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:count]).to eq(0)
      end
    end
  end
end
