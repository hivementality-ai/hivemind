# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::CreateFromTemplate do
  describe '.call' do
    let(:template) do
      create(:agent_template,
             name: "Assistant Template",
             role: "assistant",
             model_config: { "model" => "gpt-4" },
             tools_config: { "tools" => ["web_search"] },
             system_prompt: "You are a helpful assistant",
             soul_md: "# Soul\nI am an assistant.")
    end
    let(:team) { create(:team) }

    before do
      # Mock Audit::Log call
      allow(Audit::Log).to receive(:call)
      # Mock FileUtils operations
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
    end

    context 'when creating agent successfully' do
      it 'creates a new agent with template attributes' do
        result = described_class.call(template: template, team: team)

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true

        agent = result.data[:agent]
        expect(agent).to be_a(Agent)
        expect(agent).to be_persisted
        expect(agent.name).to eq(template.name)
        expect(agent.role).to eq(template.role)
        expect(agent.team).to eq(team)
        expect(agent.model_config).to eq(template.model_config)
        expect(agent.tools_config).to eq(template.tools_config)
        expect(agent.system_prompt).to eq(template.system_prompt)
      end

      it 'uses custom name when provided' do
        custom_name = "Custom Agent Name"
        result = described_class.call(template: template, name: custom_name, team: team)

        expect(result.success?).to be true
        expect(result.data[:agent].name).to eq(custom_name)
      end

      it 'creates workspace directory structure' do
        result = described_class.call(template: template, team: team)
        agent = result.data[:agent]

        expected_workspace_path = Rails.root.join("storage", "workspaces", agent.id.to_s)
        expected_memory_path = expected_workspace_path.join("memory")

        expect(FileUtils).to have_received(:mkdir_p).with(expected_workspace_path)
        expect(FileUtils).to have_received(:mkdir_p).with(expected_memory_path)
      end

      it 'writes SOUL.md file when template has soul_md' do
        result = described_class.call(template: template, team: team)
        agent = result.data[:agent]

        expected_soul_path = Rails.root.join("storage", "workspaces", agent.id.to_s, "SOUL.md")
        expect(File).to have_received(:write).with(expected_soul_path, template.soul_md)
      end

      it 'updates agent with workspace path' do
        result = described_class.call(template: template, team: team)
        agent = result.data[:agent]

        expected_workspace_path = Rails.root.join("storage", "workspaces", agent.id.to_s).to_s
        expect(agent.workspace_path).to eq(expected_workspace_path)
      end

      it 'creates audit log entry' do
        result = described_class.call(template: template, team: team)
        agent = result.data[:agent]

        expect(Audit::Log).to have_received(:call).with(
          actor: "system",
          action: "agent.created_from_template",
          resource: agent,
          metadata: {
            template_id: template.id,
            template_name: template.name
          }
        )
      end
    end

    context 'when template has no soul_md' do
      let(:template_without_soul) do
        create(:agent_template, soul_md: nil)
      end

      it 'does not write SOUL.md file' do
        described_class.call(template: template_without_soul, team: team)

        expect(File).not_to have_received(:write)
      end
    end

    context 'when no team is provided' do
      it 'creates agent without team' do
        result = described_class.call(template: template)

        expect(result.success?).to be true
        expect(result.data[:agent].team).to be_nil
      end
    end

    context 'when agent validation fails' do
      before do
        allow_any_instance_of(Agent).to receive(:save).and_return(false)
        allow_any_instance_of(Agent).to receive(:errors).and_return(
          double(full_messages: ["Name can't be blank", "Role is invalid"])
        )
      end

      it 'returns failure with validation errors' do
        result = described_class.call(template: template, team: team)

        expect(result.success?).to be false
        expect(result.error).to eq("Name can't be blank, Role is invalid")
      end

      it 'does not create workspace or audit log' do
        described_class.call(template: template, team: team)

        expect(FileUtils).not_to have_received(:mkdir_p)
        expect(Audit::Log).not_to have_received(:call)
      end
    end

    context 'when workspace setup fails' do
      before do
        allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError, "Permission denied")
      end

      it 'returns failure with error message' do
        result = described_class.call(template: template, team: team)

        expect(result.success?).to be false
        expect(result.error).to eq("Failed to create agent from template: Permission denied")
      end
    end

    context 'when audit logging fails' do
      before do
        allow(Audit::Log).to receive(:call).and_raise(StandardError, "Audit system down")
      end

      it 'returns failure with error message' do
        result = described_class.call(template: template, team: team)

        expect(result.success?).to be false
        expect(result.error).to eq("Failed to create agent from template: Audit system down")
      end
    end
  end
end