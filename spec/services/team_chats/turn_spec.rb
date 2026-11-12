# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamChats::Turn do
  let(:chat) { create(:team_chat_session) }
  let(:message) { create(:team_chat_message, team_chat_session: chat, content: "Produce an evidence table with source links.", metadata: { "keep" => true }) }
  let(:turn) { described_class.new(message) }
  let(:lead) { create(:agent, team: chat.team) }
  let(:reviewer) { create(:agent, team: chat.team) }

  before { turn.start! }

  it "starts only once and preserves unrelated metadata" do
    expect(described_class.new(message.reload).start!).to be false
    expect(message.metadata["keep"]).to be true
    turn.finish!
    expect(described_class.new(message.reload).start!).to be false
  end

  it "deduplicates repeated handoffs across instances and returns the existing result" do
    result = turn.reserve!(from: lead, target: reviewer, task: "Check  the sources")
    turn.record_result!(result.data[:handoff_id], status: "completed", result: "One source was unavailable.")
    duplicate = described_class.new(message.reload).reserve!(from: lead, target: reviewer, task: " Check\n the sources ")
    expect(duplicate).not_to be_success
    expect(duplicate.error).to include("already requested", "One source was unavailable.")
    expect(turn.prompt).to include(message.content, "One source was unavailable.")
  end

  it "limits assignments per recipient across different senders" do
    2.times { |i| expect(turn.reserve!(from: lead, target: reviewer, task: "Review #{i}")).to be_success }
    other = create(:agent, team: chat.team)
    expect(turn.reserve!(from: other, target: reviewer, task: "Another review")).not_to be_success
  end

  it "shares the total budget across all branches" do
    3.times do
      target = create(:agent, team: chat.team)
      2.times { |i| expect(turn.reserve!(from: lead, target: target, task: "Task #{i}")).to be_success }
    end
    expect(turn.reserve!(from: lead, target: reviewer, task: "Seventh task").error).to include("shared limit")
  end

  it "stops all active roots and rejects later handoffs" do
    described_class.stop_active!(chat)
    expect(turn).not_to be_running
    expect(turn.reserve!(from: lead, target: reviewer, task: "Review").error).to include("stopped")
    turn.finish!
    expect(message.reload.metadata.dig("team_turn", "status")).to eq("stopped")
  end

  it "exposes trusted SDK context only during execution and clears it on exceptions" do
    session = chat.session_for(lead)
    session.update!(metadata: session.metadata.merge("keep" => "value"))
    expect do
      turn.with_agent_context(session, depth: 3, active_agent_ids: [ lead.id ]) do
        expect(session.reload.metadata.dig(described_class::CONTEXT_KEY, "turn_message_id")).to eq(message.id)
        raise "failed execution"
      end
    end.to raise_error("failed execution")
    expect(session.reload.metadata).not_to have_key(described_class::CONTEXT_KEY)
    expect(session.metadata["keep"]).to eq("value")
  end
end
