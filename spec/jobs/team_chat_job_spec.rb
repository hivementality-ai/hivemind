# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamChatJob, type: :job do
  let(:team) { create(:team) }
  let(:agent) { create(:agent, team: team) }
  let(:user) { create(:user) }
  let(:session) { create(:team_chat_session, team: team) }

  describe "hashtag action processing" do
    it "processes hashtag actions before sending to LLM" do
      message = session.team_chat_messages.create!(
        sender_type: "user",
        sender_id: user.id,
        content: "#help"
      )

      # Mock the processor
      allow(HashtagActions::Processor).to receive(:call).and_return(
        HashtagActions::Processor::ProcessResult.new(
          bypass_llm: true,
          response: "Available actions: #remember, #forget, #search...",
          clean_message: "",
          prompt_addons: [],
          side_effects: []
        )
      )

      expect {
        TeamChatJob.perform_now(session.id, message.id)
      }.to broadcast_to("team_chat_#{session.id}")

      expect(HashtagActions::Processor).to have_received(:call)
    end

    it "strips hashtags from message when bypass_llm is false" do
      message = session.team_chat_messages.create!(
        sender_type: "user",
        sender_id: user.id,
        content: "#mood cheerful Tell me a joke"
      )

      # Mock the processor with non-bypass response
      allow(HashtagActions::Processor).to receive(:call).and_return(
        HashtagActions::Processor::ProcessResult.new(
          bypass_llm: false,
          response: "Mood set to cheerful",
          clean_message: "Tell me a joke",
          prompt_addons: ["Adjust your communication style: cheerful"],
          side_effects: []
        )
      )

      # Mock LLM adapter
      adapter = instance_double(Providers::Claude)
      allow(Providers::Resolver).to receive(:call).and_return(
        double(success?: true, data: { adapter: adapter })
      )

      allow(adapter).to receive(:chat).and_return(
        double(success?: true, data: { content: "Here's a joke!", usage: {} })
      )

      TeamChatJob.perform_now(session.id, message.id)

      # Verify the prompt addons were injected
      expect(HashtagActions::Processor).to have_received(:call)
    end

    it "bypasses LLM when hashtag action requests it" do
      message = session.team_chat_messages.create!(
        sender_type: "user",
        sender_id: user.id,
        content: "#status"
      )

      allow(HashtagActions::Processor).to receive(:call).and_return(
        HashtagActions::Processor::ProcessResult.new(
          bypass_llm: true,
          response: "Agent is operational. Model: claude-3-5-sonnet",
          clean_message: "",
          prompt_addons: [],
          side_effects: []
        )
      )

      # Ensure LLM is not called
      expect(Providers::Resolver).not_to receive(:call)

      expect {
        TeamChatJob.perform_now(session.id, message.id)
      }.to broadcast_to("team_chat_#{session.id}")
    end
  end
end
