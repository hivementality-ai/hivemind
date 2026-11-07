# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261107130000_retire_imap_gmail_tool")

RSpec.describe Tools::GmailRetirement do
  let!(:old_tool) { create(:tool, name: "gmail", executor_type: "gmail", builtin: true) }
  let!(:new_tool) { create(:tool, name: "google_gmail", executor_type: "google_gmail", builtin: true) }

  it "moves an agent's gmail assignment to google_gmail" do
    agent = create(:agent)
    AgentTool.create!(agent: agent, tool: old_tool)

    described_class.call

    expect(agent.agent_tools.reload.map(&:tool)).to eq([ new_tool ])
  end

  it "leaves no duplicate when the agent already has google_gmail" do
    agent = create(:agent)
    AgentTool.create!(agent: agent, tool: old_tool)
    AgentTool.create!(agent: agent, tool: new_tool)

    described_class.call

    expect(AgentTool.where(agent: agent).pluck(:tool_id)).to eq([ new_tool.id ])
  end

  it "moves skill bindings the same way" do
    moved = create(:skill)
    both = create(:skill)
    SkillTool.create!(skill: moved, tool: old_tool)
    SkillTool.create!(skill: both, tool: old_tool)
    SkillTool.create!(skill: both, tool: new_tool)

    described_class.call

    expect(SkillTool.where(skill: moved).pluck(:tool_id)).to eq([ new_tool.id ])
    expect(SkillTool.where(skill: both).pluck(:tool_id)).to eq([ new_tool.id ])
  end

  it "rewrites enabled tool names on agents and templates without duplicating" do
    agent = create(:agent, tools_config: { "enabled" => [ "gmail", "email", "google_gmail" ] })
    template = create(:agent_template, tools_config: { "enabled" => [ "web_search", "gmail" ] })

    described_class.call

    expect(agent.reload.tools_config["enabled"]).to eq([ "google_gmail", "email" ])
    expect(template.reload.tools_config["enabled"]).to eq([ "web_search", "google_gmail" ])
  end

  it "disables the old tool instead of deleting it" do
    described_class.call

    expect(old_tool.reload.enabled).to be false
    expect(new_tool.reload.enabled).to be true
  end

  it "is idempotent" do
    agent = create(:agent)
    AgentTool.create!(agent: agent, tool: old_tool)

    2.times { described_class.call }

    expect(agent.agent_tools.reload.map(&:tool)).to eq([ new_tool ])
  end

  it "does nothing when the old tool was never installed" do
    old_tool.destroy!

    expect { described_class.call }.not_to raise_error
    expect(new_tool.reload.enabled).to be true
  end

  it "does not offer the retired tool to an agent that had it" do
    agent = create(:agent)
    AgentTool.create!(agent: agent, tool: old_tool)

    described_class.call

    expect(agent.assigned_tools.map(&:name)).to eq([ "google_gmail" ])
  end

  it "still resolves the retired executor type to the Google executor" do
    expect(Tools::Executor.all_executors["gmail"]).to eq(Tools::GoogleGmailExecutor)
  end

  describe "migration" do
    it "runs the retirement" do
      agent = create(:agent)
      AgentTool.create!(agent: agent, tool: old_tool)

      ActiveRecord::Migration.suppress_messages { RetireImapGmailTool.new.up }

      expect(agent.agent_tools.reload.map(&:tool)).to eq([ new_tool ])
    end
  end
end
