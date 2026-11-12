# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::TalkToTeammateExecutor do
  let(:team) { create(:team, custom_soul: "Keep handoffs concise and source-linked.") }
  let(:chat) { create(:team_chat_session, team: team) }
  let(:lead) { create(:agent, name: "Lead", team: team) }
  let(:reviewer) { create(:agent, name: "Reviewer", team: team) }
  let(:session) { chat.session_for(lead) }
  let(:root) { create(:team_chat_message, team_chat_session: chat, content: "Create a reviewed evidence table.") }
  let(:turn) { TeamChats::Turn.new(root) }
  let(:adapter) { double("provider") }
  let(:config) { { session: session, team_turn_message_id: root.id, team_chat_depth: 3, active_agent_ids: [ lead.id ] } }
  let(:result) { ServiceResponse.success(data: { content: "Sources verified.", usage: { input_tokens: 20, output_tokens: 10 } }) }

  def execute(target: reviewer.name, task: "Verify these sources.", execution_config: config, caller: lead)
    described_class.new(agent: caller, config: execution_config, input: { "teammate" => target, "message" => task }).call
  end

  before do
    turn.start!
    allow(ActionCable.server).to receive(:broadcast)
    allow(Providers::Resolver).to receive(:call).and_return(ServiceResponse.success(data: { adapter: adapter }))
    allow(Budgets::Check).to receive(:call).and_return(ServiceResponse.success)
    allow(Budgets::RecordSpend).to receive(:call).and_return(ServiceResponse.success)
    allow(CostEstimator).to receive(:estimate).and_return(1)
    allow(Agents::ToolLoop).to receive(:call).and_return(result)
  end

  it "pins the original goal and team agreement beyond the recent history window" do
    create_list(:team_chat_message, 8, team_chat_session: chat, content: "Intervening discussion")
    expect(execute).to be_success
    expect(Agents::ToolLoop).to have_received(:call) do |**args|
      text = args[:messages].first[:content].map { |block| block[:text] }.join("\n")
      expect(text).to include(root.content, team.custom_soul)
      expect(args[:extra_config]).to include(team_turn_message_id: root.id, team_chat_depth: 2)
      expect(args[:messages].count { |msg| msg[:content] == "[Lead]: Verify these sources." }).to eq(1)
    end
    expect(Budgets::Check).to have_received(:call).with(agent: reviewer)
    expect(Budgets::RecordSpend).to have_received(:call).with(hash_including(agent: reviewer, input_tokens: 20, output_tokens: 10))
    expect(chat.session_for(reviewer).metadata).not_to have_key(TeamChats::Turn::CONTEXT_KEY)
    expect(root.reload.metadata.dig("team_turn", "handoffs", 0, "status")).to eq("completed")
  end

  it "avoids another provider call for duplicate requests" do
    expect(execute).to be_success
    expect(execute.error).to include("already requested", "Sources verified.")
    expect(Agents::ToolLoop).to have_received(:call).once
  end

  it "rejects self-talk, cycles and exhausted depth before calling a provider" do
    expect(execute(target: lead.name).error).to include("yourself")
    expect(execute(execution_config: config.merge(active_agent_ids: [ lead.id, reviewer.id ])).error).to include("already in")
    expect(execute(execution_config: config.merge(team_chat_depth: 0)).error).to include("depth limit")
    expect(Providers::Resolver).not_to have_received(:call)
  end

  it "rejects foreign sessions and root messages" do
    foreign = create(:team_chat_message)
    expect(execute(execution_config: config.merge(team_turn_message_id: foreign.id))).not_to be_success
    expect(execute(execution_config: config.merge(session: create(:session)))).not_to be_success
    expect(Agents::ToolLoop).not_to have_received(:call)
  end

  it "recovers SDK handoff state from server-written session context" do
    turn.with_agent_context(session, depth: 3, active_agent_ids: [ lead.id ]) do
      expect(execute(execution_config: { session: session })).to be_success
    end
    expect(execute(task: "New task", execution_config: { session: session }).error).to include("No active team turn")
  end

  it "blocks a target whose budget is exhausted" do
    allow(Budgets::Check).to receive(:call).with(agent: reviewer).and_return(ServiceResponse.failure(error: "limit"))
    expect(execute.error).to include("budget limit")
    expect(Agents::ToolLoop).not_to have_received(:call)
  end

  it "supplies the nested OAuth provider with its own session and bounded callback context" do
    oauth_adapter = instance_double(Providers::AnthropicAdapter)
    allow(oauth_adapter).to receive(:is_a?).with(Providers::AnthropicAdapter).and_return(true)
    allow(oauth_adapter).to receive(:oauth_token?).and_return(true)
    allow(Providers::Resolver).to receive(:call).and_return(ServiceResponse.success(data: { adapter: oauth_adapter }))
    allow(Agents::ToolLoop).to receive(:call) do |**args|
      target_session = args[:session]
      expect(args[:options]).to include(agent_id: reviewer.id, session_id: target_session.id)
      expect(args[:options][:tool_definitions]).to include(SystemTool::TALK_TO_TEAMMATE.to_llm_tool)
      context = target_session.reload.metadata.fetch(TeamChats::Turn::CONTEXT_KEY)
      expect(context).to include("turn_message_id" => root.id, "depth" => 2)
      expect(context["active_agent_ids"]).to include(lead.id, reviewer.id)
      result
    end
    expect(execute).to be_success
  end

  it "returns provider errors as failed work" do
    allow(Agents::ToolLoop).to receive(:call).and_return(ServiceResponse.failure(error: "Unavailable"))
    expect(execute.error).to include("Unavailable")
    expect(root.reload.metadata.dig("team_turn", "handoffs", 0, "status")).to eq("failed")
    expect(chat.team_chat_messages.where(sender_id: reviewer.id, sender_type: "agent")).to be_empty
  end

  it "does not turn an empty response into a successful handoff" do
    allow(Agents::ToolLoop).to receive(:call).and_return(ServiceResponse.success(data: { content: "[Reviewer]: " }))
    expect(execute).not_to be_success
  end

  it "propagates cancellation and prevents any subsequent handoffs" do
    allow(Agents::ToolLoop).to receive(:call).and_raise(AgentInterrupted)
    expect { execute }.to raise_error(AgentInterrupted)
    expect(turn).not_to be_running
    expect(execute(task: "Another task").error).to include("stopped")
    expect(root.reload.metadata.dig("team_turn", "handoffs", 0, "status")).to eq("interrupted")
  end

  it "propagates cancellation through the system-tool dispatcher" do
    allow(Agents::ToolLoop).to receive(:call).and_raise(AgentInterrupted)
    turn.with_agent_context(session, depth: 3, active_agent_ids: [ lead.id ]) do
      expect do
        Tools::Executor.call(tool: SystemTool::TALK_TO_TEAMMATE, agent: lead, session: session,
          input: { "teammate" => reviewer.name, "message" => "Review the sources" })
      end.to raise_error(AgentInterrupted)
    end
    expect(turn).not_to be_running
  end
  it "marks the target as working during the handoff and idle afterwards" do
    allow(Agents::ToolLoop).to receive(:call) do
      expect(reviewer.reload.status).to eq("thinking")
      result
    end
    expect(execute).to be_success
    expect(reviewer.reload).to be_idle
  end

  it "leaves the teammate idle when execution raises" do
    allow(Agents::ToolLoop).to receive(:call).and_raise("boom")
    expect(execute).not_to be_success
    expect(reviewer.reload).to be_idle
  end
end
