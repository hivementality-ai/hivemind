# frozen_string_literal: true

require "rails_helper"

RSpec.describe "db/seeds/tools.rb" do
  let(:seed_file) { Rails.root.join("db/seeds/tools.rb") }

  def run_seed
    original = $stdout
    $stdout = StringIO.new
    silence_warnings { load seed_file }
  ensure
    $stdout = original
  end

  it "seeds one Gmail tool and no retired gmail tool" do
    run_seed

    expect(Tool.enabled.where(name: %w[gmail google_gmail]).pluck(:name)).to eq([ "google_gmail" ])
  end

  it "does not re-enable a retired gmail row" do
    create(:tool, name: "gmail", executor_type: "gmail", builtin: true, enabled: false)

    run_seed

    expect(Tool.find_by!(name: "gmail").enabled).to be false
  end

  it "moves agents that had gmail onto google_gmail without duplicates" do
    old_tool = create(:tool, name: "gmail", executor_type: "gmail", builtin: true)
    agent = create(:agent)
    AgentTool.create!(agent: agent, tool: old_tool)

    run_seed

    expect(agent.agent_tools.reload.map { |at| at.tool.name }).to eq([ "google_gmail" ])
  end

  it "offers the reply action on google_gmail" do
    run_seed

    actions = Tool.find_by!(name: "google_gmail").parameters_schema.dig("properties", "action", "enum")
    expect(actions).to include("inbox", "reply")
  end

  it "points the scheduled-task description at a real tool name" do
    run_seed

    cron = Tool.find_by!(name: "cron")
    expect(cron.description).to include("google_gmail")
    expect(cron.description).not_to match(/\(gmail,/)
    expect(Tool.exists?(name: "google_gmail", enabled: true)).to be true
  end
end
