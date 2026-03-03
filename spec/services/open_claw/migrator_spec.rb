# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::Migrator do
  after { cleanup_openclaw_workspace(@workspace_path) if @workspace_path }

  describe ".call" do
    context "with a valid workspace" do
      before do
        @workspace_path = create_openclaw_workspace(
          identity: "**Name:** Aria\n**Emoji:** 🦊\n**Vibe:** Playful",
          soul: "You are a helpful assistant.",
          memory: "## Preferences\nUser prefers dark mode and always uses Vim.",
          skills: {
            "greet.SKILL.md" => default_skill_md(name: "greet", description: "Greets users", content: "Say hello warmly.")
          },
          conversations: {
            "chat1.json" => [{ "role" => "user", "content" => "Hello" }]
          },
          config: {
            "channels" => [
              { "type" => "slack", "name" => "Work Slack", "config" => { "channel_id" => "C123" } }
            ],
            "tools" => [
              { "name" => "deploy_tool", "description" => "Deploys", "script" => "echo deploy" }
            ]
          }
        )
      end

      it "imports all artifacts and returns success" do
        result = described_class.call(workspace_path: @workspace_path)

        expect(result).to be_success
        report = result.data[:report]

        expect(report.identity_imported).to be true
        expect(report.agent.name).to eq("Aria")
        expect(report.memories_created).to be > 0
        expect(report.skills_imported.size).to eq(1)
        expect(report.channels_created.size).to eq(1)
        expect(report.sessions_created).to eq(1)
        expect(report.tools_created.size).to eq(1)
        expect(report.success?).to be true
      end

      it "creates the agent record" do
        described_class.call(workspace_path: @workspace_path)

        agent = Agent.find_by(slug: "aria")
        expect(agent).to be_present
        expect(agent.custom_instructions).to include("helpful assistant")
      end

      it "creates channels as disabled" do
        described_class.call(workspace_path: @workspace_path)

        channel = Channel.find_by(name: "Work Slack")
        expect(channel).to be_present
        expect(channel.enabled).to be false
      end
    end

    context "with missing config.json" do
      before do
        @workspace_path = Dir.mktmpdir("openclaw_test_")
      end

      it "returns failure" do
        result = described_class.call(workspace_path: @workspace_path)

        expect(result).not_to be_success
        expect(result.error).to match(/Missing config\.json/)
      end
    end

    context "with non-existent directory" do
      it "returns failure" do
        result = described_class.call(workspace_path: "/tmp/nonexistent_openclaw_dir_#{SecureRandom.hex}")

        expect(result).not_to be_success
        expect(result.error).to match(/does not exist/)
      end
    end

    context "with dry_run: true" do
      before do
        @workspace_path = create_openclaw_workspace(
          identity: "**Name:** DryRunBot\n**Emoji:** 🤖\n**Vibe:** Cautious",
          memory: "## Facts\nUser's name is Matt and works at Acme.",
          config: { "channels" => [], "tools" => [] }
        )
      end

      it "does not persist records" do
        agent_count_before = Agent.count
        memory_count_before = MemoryEntry.count

        result = described_class.call(workspace_path: @workspace_path, dry_run: true)

        expect(result).to be_success
        expect(Agent.count).to eq(agent_count_before)
        expect(MemoryEntry.count).to eq(memory_count_before)
      end

      it "still returns a populated report" do
        result = described_class.call(workspace_path: @workspace_path, dry_run: true)

        report = result.data[:report]
        expect(report.identity_imported).to be true
        expect(report.agent.name).to eq("DryRunBot")
      end
    end

    context "with partial parser failure" do
      before do
        @workspace_path = create_openclaw_workspace(
          identity: "**Name:** PartialBot",
          config: { "channels" => [], "tools" => [] }
        )
        # Write invalid JSON to conversations to cause parser failure
        conv_dir = File.join(@workspace_path, "conversations")
        FileUtils.mkdir_p(conv_dir)
        File.write(File.join(conv_dir, "bad.json"), "not valid json{{{")
      end

      it "continues after non-fatal parser failure and adds warning" do
        result = described_class.call(workspace_path: @workspace_path)

        expect(result).to be_success
        report = result.data[:report]
        expect(report.identity_imported).to be true
        expect(report.warnings).to include(a_string_matching(/Conversation parser failed/))
      end
    end

    context "with explicit agent_slug" do
      before do
        @workspace_path = create_openclaw_workspace(
          identity: "**Name:** Aria",
          config: { "channels" => [], "tools" => [] }
        )
      end

      it "uses the provided slug" do
        result = described_class.call(workspace_path: @workspace_path, agent_slug: "my_custom_slug")

        expect(result).to be_success
        expect(result.data[:report].agent.slug).to eq("my_custom_slug")
      end
    end

    context "transaction rollback on identity failure" do
      before do
        @workspace_path = create_openclaw_workspace(
          identity: "**Name:** Aria",
          memory: "## Facts\nSome important memory content here.",
          config: { "channels" => [], "tools" => [] }
        )
        # Force identity parser to fail
        allow(OpenClaw::IdentityParser).to receive(:call).and_return(
          ServiceResponse.failure(error: "Agent creation failed")
        )
      end

      it "rolls back all changes when identity fails" do
        agent_count_before = Agent.count
        memory_count_before = MemoryEntry.count

        described_class.call(workspace_path: @workspace_path)

        expect(Agent.count).to eq(agent_count_before)
        expect(MemoryEntry.count).to eq(memory_count_before)
      end
    end

    describe "markers detection" do
      before do
        @workspace_path = create_openclaw_workspace(
          identity: "**Name:** Aria",
          soul: "Be helpful.",
          memory: "## Notes\nSome notes about the user's preferences.",
          openclaw_marker: true,
          config: { "channels" => [], "tools" => [] }
        )
      end

      it "records found markers" do
        result = described_class.call(workspace_path: @workspace_path)

        report = result.data[:report]
        expect(report.markers_found).to include("IDENTITY.md", "SOUL.md", "MEMORY.md", ".openclaw")
      end
    end
  end
end
