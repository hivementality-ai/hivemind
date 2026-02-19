# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::CreateFromTemplate do
  let(:team) { create(:team) }
  let(:skills) { create_list(:skill, 2, enabled: true) }

  let(:template) do
    create(
      :agent_template,
      name: "Test Template",
      role: "Tester",
      system_prompt: "You are a test agent",
      model_config: { provider: "anthropic", model: "claude-haiku-4-5" },
      tools_config: { enabled: [ "file_read", "shell" ] },
      skills_config: { enabled: skills.map(&:name) },
      soul_md: "# Test Soul\n\nYou are a test agent."
    )
  end

  describe ".call" do
    subject(:result) { described_class.call(template: template, name: name, team: team) }

    context "with custom name" do
      let(:name) { "Custom Agent Name" }

      it "creates agent with custom name" do
        expect(result.success?).to be true
        agent = result.data[:agent]

        expect(agent.name).to eq("Custom Agent Name")
        expect(agent.role).to eq("Tester")
        expect(agent.system_prompt).to eq("You are a test agent")
        expect(agent.model_config).to eq({ "provider" => "anthropic", "model" => "claude-haiku-4-5" })
        expect(agent.tools_config).to eq({ "enabled" => [ "file_read", "shell" ] })
      end

      it "assigns skills to the agent" do
        expect(result.success?).to be true
        agent = result.data[:agent]

        expect(agent.skills.pluck(:name)).to match_array(skills.map(&:name))
      end

      it "creates workspace directory and files" do
        expect(result.success?).to be true
        agent = result.data[:agent]

        expect(agent.workspace_path).to be_present
        expect(Dir.exist?(agent.workspace_path)).to be true

        soul_path = File.join(agent.workspace_path, "SOUL.md")
        expect(File.exist?(soul_path)).to be true
        expect(File.read(soul_path)).to eq("# Test Soul\n\nYou are a test agent.")

        memory_path = File.join(agent.workspace_path, "memory")
        expect(Dir.exist?(memory_path)).to be true
      end

      it "calls SyncSkillTools when skills are assigned" do
        expect(Agents::SyncSkillTools).to receive(:call).with(agent: an_instance_of(Agent))
        result
      end

      it "logs the creation" do
        expect(Audit::Record).to receive(:call).with(
          actor_type: "system",
          actor_id: "template_deploy",
          action: "agent.created_from_template",
          resource: { "type" => "Agent", "id" => an_instance_of(Integer) },
          metadata: { template_id: template.id, template_name: "Test Template" }
        )
        result
      end
    end

    context "with default name" do
      let(:name) { nil }

      it "uses template name" do
        expect(result.success?).to be true
        agent = result.data[:agent]
        expect(agent.name).to eq("Test Template")
      end
    end

    context "when template has empty skills_config" do
      let(:name) { "Test Agent" }
      let(:template) do
        create(
          :agent_template,
          name: "Empty Skills Template",
          skills_config: { enabled: [] }
        )
      end

      it "succeeds without assigning skills" do
        expect(result.success?).to be true
        agent = result.data[:agent]
        expect(agent.skills).to be_empty
      end

      it "does not call SyncSkillTools" do
        expect(Agents::SyncSkillTools).not_to receive(:call)
        result
      end
    end

    context "when template has non-existent skills" do
      let(:name) { "Test Agent" }
      let(:template) do
        create(
          :agent_template,
          name: "Bad Skills Template",
          skills_config: { enabled: [ "nonexistent_skill" ] }
        )
      end

      it "succeeds but does not assign non-existent skills" do
        expect(result.success?).to be true
        agent = result.data[:agent]
        expect(agent.skills).to be_empty
      end
    end

    context "when agent creation fails" do
      let(:name) { "" } # Invalid name to trigger validation error

      it "returns failure" do
        expect(result.success?).to be false
        expect(result.error).to include("Name can't be blank")
      end
    end

    context "when an exception occurs" do
      let(:name) { "Test Agent" }

      before do
        allow(Agent).to receive(:new).and_raise(StandardError.new("Test error"))
      end

      it "returns failure with error message" do
        expect(result.success?).to be false
        expect(result.error).to eq("Failed to create agent from template: Test error")
      end
    end
  end
end