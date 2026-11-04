# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::TalkToTeammateExecutor do
  let(:team) { create(:team) }
  let(:team_chat_session) { create(:team_chat_session, team: team) }
  let!(:caller_agent) { create(:agent, team: team, name: "Alice", enabled: true) }
  let!(:target) { create(:agent, team: team, name: "Vida", enabled: true) }
  let(:session) { create(:session, agent: caller_agent, metadata: { "team_chat_session_id" => team_chat_session.id }) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    adapter = double("adapter")
    allow(Providers::Resolver).to receive(:call).and_return(double(success?: true, data: { adapter: adapter }))
  end

  def run_executor
    described_class.new(
      agent: caller_agent,
      input: { "teammate" => "Vida", "message" => "thoughts?" },
      config: { session: session, team_chat_depth: 2 }
    ).call
  end

  it "shows the teammate as working while it answers and idle afterwards" do
    status_during = nil
    allow(Agents::ToolLoop).to receive(:call) do
      status_during = target.reload.status
      double(success?: true, data: { content: "sure", usage: {} })
    end

    run_executor

    expect(status_during).to eq("thinking")
    expect(target.reload).to be_idle
  end

  it "leaves the teammate idle when the answer fails" do
    allow(Agents::ToolLoop).to receive(:call).and_raise(RuntimeError, "boom")

    expect(run_executor).not_to be_success
    expect(target.reload).to be_idle
  end
end
