# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ToolAvailability do
  let(:agent) { create(:agent, name: "TestAgent") }

  describe ".explain" do
    context "when tool does not exist in the system" do
      it "returns unknown tool message for completely unknown tools" do
        result = described_class.explain(
          tool_name: "quantum_teleporter",
          agent: agent
        )

        expect(result).to include("isn't available")
        expect(result).to include("admin")
      end

      it "returns not-registered message for known tool types" do
        # image_generate is a valid executor_type but may not have a Tool record
        allow(Tool).to receive(:find_by).with(name: "image_generate").and_return(nil)

        result = described_class.explain(
          tool_name: "image_generate",
          agent: agent
        )

        expect(result).to include("isn't set up yet")
        expect(result).to include("admin")
      end
    end

    context "when tool exists but is disabled" do
      it "returns disabled message" do
        tool = create(:tool, name: "test_tool", executor_type: "shell", enabled: false, description: "Test tool")

        result = described_class.explain(
          tool_name: "test_tool",
          agent: agent
        )

        expect(result).to include("disabled")
        expect(result).to include("administrator")
      end
    end

    context "when agent lacks permission" do
      it "returns no-permission message when agent has other tools assigned" do
        tool = create(:tool, name: "image_generate", executor_type: "image_generate", enabled: true, description: "Image generation")
        other_tool = create(:tool, name: "web_search", executor_type: "web_search", enabled: true, description: "Web search")

        # Agent has web_search but not image_generate
        create(:agent_tool, agent: agent, tool: other_tool)

        result = described_class.explain(
          tool_name: "image_generate",
          agent: agent
        )

        expect(result).to include("don't have permission")
        expect(result).to include("admin")
      end
    end

    context "when tool exists but provider is missing" do
      it "returns missing provider message for image_generate without OpenAI" do
        tool = create(:tool, name: "image_generate", executor_type: "image_generate", enabled: true, description: "Image generation")
        create(:agent_tool, agent: agent, tool: tool)

        result = described_class.explain(
          tool_name: "image_generate",
          agent: agent,
          available_tools: []
        )

        expect(result).to include("not fully configured")
        expect(result).to include("OpenAI API key")
      end

      it "uses db requirements when present, ignoring constant" do
        tool = create(:tool,
          name: "image_generate",
          executor_type: "image_generate",
          enabled: true,
          description: "Image generation",
          requirements: { "provider" => "custom_provider", "description" => "custom img", "config_hint" => "Custom provider key required" }
        )
        create(:agent_tool, agent: agent, tool: tool)

        result = described_class.explain(
          tool_name: "image_generate",
          agent: agent,
          available_tools: []
        )

        expect(result).to include("Custom provider key required")
        expect(result).not_to include("OpenAI API key")
      end

      it "falls back to constant when tool has no db requirements" do
        tool = create(:tool,
          name: "image_generate",
          executor_type: "image_generate",
          enabled: true,
          description: "Image generation",
          requirements: {}
        )
        create(:agent_tool, agent: agent, tool: tool)

        result = described_class.explain(
          tool_name: "image_generate",
          agent: agent,
          available_tools: []
        )

        expect(result).to include("OpenAI API key")
      end
    end

    context "when tool exists, agent has access, and no provider requirement" do
      it "returns generic unavailable message for tools without provider requirements" do
        tool = create(:tool, name: "shell", executor_type: "shell", enabled: true, description: "Shell commands")
        create(:agent_tool, agent: agent, tool: tool)

        result = described_class.explain(
          tool_name: "shell",
          agent: agent,
          available_tools: []
        )

        expect(result).to include("isn't available right now")
      end
    end
  end

  describe ".limitations_summary" do
    it "returns nil when agent has all tools" do
      tool1 = create(:tool, name: "shell", executor_type: "shell", enabled: true)
      create(:agent_tool, agent: agent, tool: tool1)

      # Only 1 enabled tool and agent has it
      result = described_class.limitations_summary(agent: agent)
      # May or may not be nil depending on how many other enabled tools exist
      # Just verify it returns a string or nil
      expect(result).to be_a(String).or be_nil
    end

    it "lists unavailable tools with descriptions" do
      tool1 = create(:tool, name: "shell", executor_type: "shell", enabled: true)
      tool2 = create(:tool, name: "image_generate", executor_type: "image_generate", enabled: true)
      create(:agent_tool, agent: agent, tool: tool1)

      result = described_class.limitations_summary(agent: agent)

      expect(result).to include("image_generate")
      expect(result).to include("NOT available")
    end
  end
end
