# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryExtractionJob, type: :job do
  let(:agent)   { create(:agent, name: "Marty McFly", model_provider: "anthropic", llm_model: "claude-haiku-4-5") }
  let(:adapter) { instance_double(Providers::AnthropicAdapter) }
  let(:resolver_success) { double(success?: true, data: { adapter: adapter }) }

  before do
    allow(Providers::Resolver).to receive(:call).and_return(resolver_success)
    allow(Memory::Store).to receive(:call)
  end

  def stub_llm(content)
    allow(adapter).to receive(:chat).and_return(
      double(success?: true, data: { content: content })
    )
  end

  describe ".extraction_prompt" do
    # A user greeting the agent by name ("hey marty") used to be extracted as
    # "the user's name is Marty" — the extractor had no idea who the agent was,
    # so vocatives aimed at the agent were stored as the user's identity.
    it "names the agent and forbids inferring the user's name from vocatives" do
      prompt = described_class.extraction_prompt("Marty McFly")

      expect(prompt).to include("an AI agent named Marty McFly")
      expect(prompt).to include("NOT the user's name")
      expect(prompt).to include("Never infer the user's own name")
    end
  end

  describe "#perform" do
    it "sends the agent-aware prompt to the LLM" do
      stub_llm("[]")

      described_class.perform_now(agent.id, "hey marty how is it going", "Hey! All good here.")

      expect(adapter).to have_received(:chat) do |messages:, **|
        system_msg = messages.find { |m| m[:role] == "system" }
        expect(system_msg[:content]).to include("an AI agent named Marty McFly")
      end
    end

    it "stores valid extracted memories" do
      stub_llm('[{"content": "User prefers PRs over direct edits", "type": "preference", "importance": 0.9, "supersedes": null}]')

      described_class.perform_now(agent.id, "always send me a PR please", "Got it, PRs from now on.")

      expect(Memory::Store).to have_received(:call).with(
        hash_including(agent: agent, content: "User prefers PRs over direct edits", memory_type: "preference")
      )
    end

    it "stores nothing when the LLM returns an empty array" do
      stub_llm("[]")

      described_class.perform_now(agent.id, "hey marty how is it going", "Hey! All good here.")

      expect(Memory::Store).not_to have_received(:call)
    end

    it "skips trivial exchanges without calling the LLM" do
      allow(adapter).to receive(:chat)

      described_class.perform_now(agent.id, "hi", "hello!")

      expect(adapter).not_to have_received(:chat)
    end
  end
end

RSpec.describe MemoryConsolidationJob, type: :job do
  describe ".extraction_prompt" do
    it "names the agent and forbids inferring the user's name from vocatives" do
      prompt = described_class.extraction_prompt("Marty McFly")

      expect(prompt).to include("an AI agent named Marty McFly")
      expect(prompt).to include("NOT the user's name")
      expect(prompt).not_to include("User's name is Alex")
    end
  end
end
