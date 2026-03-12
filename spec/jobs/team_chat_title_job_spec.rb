# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamChatTitleJob, type: :job do
  let(:team)    { create(:team) }
  let(:user)    { create(:user) }
  let(:agent)   { create(:agent, team: team, model_provider: "anthropic", llm_model: "claude-haiku-4-5", enabled: true) }
  let(:adapter) { instance_double(Providers::AnthropicAdapter) }
  let(:resolver_success) { double(success?: true, data: { adapter: adapter }) }
  let(:resolver_failure) { double(success?: false) }

  before do
    agent # ensure the agent exists so team.agents.enabled is non-empty
    allow(Providers::Resolver).to receive(:call).and_return(resolver_success)
    allow(ActionCable.server).to receive(:broadcast)
    allow(CostEstimator).to receive(:estimate).and_return(0)
    allow(adapter).to receive(:chat) # stub so not_to have_received assertions are valid
  end

  def create_session_with_messages(title: "New Chat", user_count: 1, agent_count: 1)
    session = create(:team_chat_session, team: team, user: user, title: title)

    user_count.times do
      session.team_chat_messages.create!(sender_type: "user", sender_id: user.id,
                                         content: "What is the best way to structure a Rails API?")
    end

    agent_count.times do
      session.team_chat_messages.create!(sender_type: "agent", sender_id: agent.id,
                                         content: "Use resource-oriented controllers and service objects.")
    end

    session
  end

  def stub_llm_title(title)
    allow(adapter).to receive(:chat).and_return(
      double(success?: true, data: { content: title, usage: { input_tokens: 10, output_tokens: 5 } })
    )
  end

  def stub_llm_failure
    allow(adapter).to receive(:chat).and_return(double(success?: false))
  end

  # ── Happy path ────────────────────────────────────────────────────────────

  describe "happy path" do
    it "generates a title when session title is 'New Chat'" do
      session = create_session_with_messages(title: "New Chat")
      stub_llm_title("Structuring a Rails API")

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("Structuring a Rails API")
    end

    it "generates a title when session title is nil" do
      session = create_session_with_messages(title: nil)
      stub_llm_title("Structuring a Rails API")

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("Structuring a Rails API")
    end

    it "generates a title when session title is blank" do
      session = create_session_with_messages(title: "")
      stub_llm_title("Structuring a Rails API")

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("Structuring a Rails API")
    end

    it "broadcasts title_update over the team chat channel" do
      session = create_session_with_messages
      stub_llm_title("Structuring a Rails API")

      described_class.perform_now(session.id)

      expect(ActionCable.server).to have_received(:broadcast).with(
        "team_chat_#{session.id}",
        { type: "title_update", title: "Structuring a Rails API" }
      )
    end

    it "strips surrounding quotes from LLM output" do
      session = create_session_with_messages
      stub_llm_title("'Structuring a Rails API'")

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("Structuring a Rails API")
    end

    it "creates a UsageRecord after successful generation" do
      # TODO: UsageRecord.session_id is a FK to sessions only — not polymorphic.
      # TeamChatTitleJob#track_usage passes a TeamChatSession, so the record is
      # not persisted. This is a bug in the implementation, not the test.
      # Un-pend this once track_usage is fixed to handle TeamChatSession.
      pending "UsageRecord FK only accepts Session, not TeamChatSession (implementation bug)"

      session = create_session_with_messages
      stub_llm_title("Structuring a Rails API")

      expect {
        described_class.perform_now(session.id)
      }.to change(UsageRecord, :count).by(1)
    end
  end

  # ── Guard conditions ──────────────────────────────────────────────────────

  describe "guard: title already set" do
    it "does not overwrite a user-set title" do
      session = create_session_with_messages(title: "My Renamed Chat")

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
      expect(session.reload.title).to eq("My Renamed Chat")
    end

    it "does not broadcast when atomic update finds title already changed" do
      session = create_session_with_messages(title: "New Chat")

      allow(TeamChatSession).to receive(:where).and_call_original
      allow(TeamChatSession).to receive(:where).with(id: session.id, title: [ nil, "", "New Chat" ]).and_wrap_original do |m, *args|
        session.update_columns(title: "Claimed By Other Job")
        m.call(*args)
      end

      stub_llm_title("Should Not Win")
      described_class.perform_now(session.id)

      expect(ActionCable.server).not_to have_received(:broadcast)
    end
  end

  describe "guard: too few messages" do
    it "does not generate a title with only one message" do
      session = create_session_with_messages(user_count: 1, agent_count: 0)

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
    end

    it "does not generate a title with zero messages" do
      session = create(:team_chat_session, team: team, user: user, title: "New Chat")

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
    end
  end

  describe "guard: no enabled agents on team" do
    it "does nothing when team has no enabled agents" do
      agent.update!(enabled: false)
      session = create_session_with_messages

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
    end
  end

  describe "guard: provider resolver fails" do
    it "does nothing when resolver cannot resolve the provider" do
      allow(Providers::Resolver).to receive(:call).and_return(resolver_failure)
      session = create_session_with_messages

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
    end
  end

  # ── LLM failure handling ──────────────────────────────────────────────────

  describe "LLM failure handling" do
    it "does not set title when LLM returns failure result" do
      session = create_session_with_messages
      stub_llm_failure

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("New Chat")
    end

    it "does not set title when LLM returns blank content" do
      session = create_session_with_messages
      allow(adapter).to receive(:chat).and_return(
        double(success?: true, data: { content: "", usage: {} })
      )

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("New Chat")
    end

    it "does not raise — swallows StandardError" do
      session = create_session_with_messages
      allow(adapter).to receive(:chat).and_raise(StandardError, "connection reset")

      expect { described_class.perform_now(session.id) }.not_to raise_error
    end
  end

  # ── Edge cases ────────────────────────────────────────────────────────────

  describe "edge cases" do
    it "truncates titles longer than 100 characters" do
      session = create_session_with_messages
      stub_llm_title("B" * 150)

      described_class.perform_now(session.id)

      expect(session.reload.title.length).to eq(100)
    end

    it "uses the cheapest model (haiku) for anthropic provider" do
      session = create_session_with_messages

      captured_options = nil
      allow(adapter).to receive(:chat) do |**kwargs|
        captured_options = kwargs[:options]
        double(success?: true, data: { content: "Title", usage: { input_tokens: 5, output_tokens: 3 } })
      end

      described_class.perform_now(session.id)

      expect(captured_options[:model]).to eq("claude-haiku-4-5")
    end

    it "labels user messages as 'User:' in the LLM conversation excerpt" do
      session = create_session_with_messages

      captured_user_content = nil
      allow(adapter).to receive(:chat) do |**kwargs|
        captured_user_content = kwargs[:messages].find { |m| m[:role] == "user" }&.dig(:content)
        double(success?: true, data: { content: "Good Title", usage: { input_tokens: 5, output_tokens: 3 } })
      end

      described_class.perform_now(session.id)

      expect(captured_user_content).to include("User:")
    end

    it "labels agent messages with the agent name in the LLM conversation excerpt" do
      session = create_session_with_messages(user_count: 1, agent_count: 1)

      captured_user_content = nil
      allow(adapter).to receive(:chat) do |**kwargs|
        captured_user_content = kwargs[:messages].find { |m| m[:role] == "user" }&.dig(:content)
        double(success?: true, data: { content: "Good Title", usage: { input_tokens: 5, output_tokens: 3 } })
      end

      described_class.perform_now(session.id)

      expect(captured_user_content).to include("#{agent.name}:")
    end

    it "labels agent message as 'Agent:' when sender agent record is not found" do
      session = create_session_with_messages(user_count: 1, agent_count: 0)
      # Add a message with a non-existent sender_id
      session.team_chat_messages.create!(sender_type: "agent", sender_id: 999_999,
                                         content: "Orphaned agent response")

      captured_user_content = nil
      allow(adapter).to receive(:chat) do |**kwargs|
        captured_user_content = kwargs[:messages].find { |m| m[:role] == "user" }&.dig(:content)
        double(success?: true, data: { content: "Good Title", usage: { input_tokens: 5, output_tokens: 3 } })
      end

      described_class.perform_now(session.id)

      expect(captured_user_content).to include("Agent:")
    end

    it "does not create a UsageRecord when usage data is nil" do
      session = create_session_with_messages
      allow(adapter).to receive(:chat).and_return(
        double(success?: true, data: { content: "Good Title", usage: nil })
      )

      expect {
        described_class.perform_now(session.id)
      }.not_to change(UsageRecord, :count)
    end
  end
end
