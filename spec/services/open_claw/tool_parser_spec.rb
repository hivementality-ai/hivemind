# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::ToolParser do
  let(:agent) { create(:agent) }

  after { cleanup_openclaw_workspace(@workspace_path) if @workspace_path }

  describe ".call" do
    context "with custom tools" do
      before do
        @workspace_path = create_openclaw_workspace(
          config: {
            "channels" => [],
            "tools" => [
              {
                "name" => "deploy_app",
                "description" => "Deploys the application",
                "script" => "cd /app && ./deploy.sh",
                "parameters" => { "properties" => { "env" => { "type" => "string" } }, "required" => [] }
              }
            ]
          }
        )
      end

      it "creates custom tools" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:created].size).to eq(1)
        expect(result.data[:created].first[:name]).to eq("deploy_app")
      end

      it "creates Tool records with correct attributes" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        tool = Tool.find_by(name: "deploy_app")
        expect(tool.executor_type).to eq("custom_script")
        expect(tool.builtin).to be false
        expect(tool.script_template).to eq("cd /app && ./deploy.sh")
      end

      it "creates AgentTool join records" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(AgentTool.exists?(agent: agent, tool: Tool.find_by(name: "deploy_app"))).to be true
      end
    end

    context "with builtin tool name collision" do
      before do
        create(:tool, :builtin, name: "shell_command")
        @workspace_path = create_openclaw_workspace(
          config: {
            "channels" => [],
            "tools" => [
              { "name" => "shell_command", "description" => "Run shell commands", "script" => "bash -c" }
            ]
          }
        )
      end

      it "skips tools that collide with builtins" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:skipped].size).to eq(1)
        expect(result.data[:skipped].first[:reason]).to match(/builtin/)
      end
    end

    context "idempotent re-run" do
      before do
        @workspace_path = create_openclaw_workspace(
          config: {
            "channels" => [],
            "tools" => [
              { "name" => "my_tool", "description" => "A tool", "script" => "echo hi" }
            ]
          }
        )
      end

      it "does not create duplicate tools" do
        described_class.call(workspace_path: @workspace_path, agent: agent)
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(Tool.where(name: "my_tool").count).to eq(1)
      end
    end

    context "without tools in config" do
      before do
        @workspace_path = create_openclaw_workspace(
          config: { "channels" => [], "tools" => [] }
        )
      end

      it "returns empty results" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:created]).to be_empty
      end
    end

    context "tool config sanitization" do
      before do
        @workspace_path = create_openclaw_workspace(
          config: {
            "channels" => [],
            "tools" => [
              {
                "name" => "api_caller",
                "description" => "Calls an API",
                "script" => "curl $URL",
                "config" => { "url" => "https://api.example.com", "api_key" => "sk-secret123" }
              }
            ]
          }
        )
      end

      it "strips credential keys from tool config" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        tool = Tool.find_by(name: "api_caller")
        expect(tool.config["url"]).to eq("https://api.example.com")
        expect(tool.config).not_to have_key("api_key")
      end
    end
  end
end
