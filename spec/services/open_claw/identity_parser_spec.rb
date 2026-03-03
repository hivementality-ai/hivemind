# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::IdentityParser do
  let(:workspace_path) do
    create_openclaw_workspace(
      identity: "**Name:** Aria\n**Emoji:** 🦊\n**Vibe:** Playful",
      soul: "You are a playful assistant named Aria."
    )
  end

  after { cleanup_openclaw_workspace(workspace_path) }

  describe ".call" do
    context "with valid identity" do
      it "creates a new agent" do
        result = described_class.call(workspace_path: workspace_path)

        expect(result).to be_success
        expect(result.data[:agent].name).to eq("Aria")
        expect(result.data[:agent].slug).to be_present
        expect(result.data[:created]).to be true
      end

      it "applies SOUL.md as custom instructions" do
        result = described_class.call(workspace_path: workspace_path)

        expect(result.data[:agent].custom_instructions).to eq("You are a playful assistant named Aria.")
      end
    end

    context "with explicit agent_slug" do
      it "uses the provided slug" do
        result = described_class.call(workspace_path: workspace_path, agent_slug: "custom_slug")

        expect(result).to be_success
        expect(result.data[:agent].slug).to eq("custom_slug")
      end
    end

    context "when agent already exists" do
      let!(:existing_agent) { create(:agent, name: "Aria", slug: "aria") }

      it "finds the existing agent" do
        result = described_class.call(workspace_path: workspace_path, agent_slug: "aria")

        expect(result).to be_success
        expect(result.data[:agent].id).to eq(existing_agent.id)
        expect(result.data[:created]).to be false
      end
    end

    context "without IDENTITY.md" do
      let(:workspace_path) do
        create_openclaw_workspace(identity: nil)
      end

      it "creates agent with default name" do
        result = described_class.call(workspace_path: workspace_path)

        expect(result).to be_success
        expect(result.data[:agent].name).to eq("Imported Agent")
      end
    end

    context "without SOUL.md" do
      let(:workspace_path) do
        create_openclaw_workspace(
          identity: "**Name:** Aria\n**Emoji:** 🦊\n**Vibe:** Playful",
          soul: nil
        )
      end

      it "creates agent without custom instructions" do
        result = described_class.call(workspace_path: workspace_path)

        expect(result).to be_success
        expect(result.data[:agent].custom_instructions).to be_blank
      end
    end
  end
end
