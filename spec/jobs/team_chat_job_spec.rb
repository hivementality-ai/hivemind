# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamChatJob, type: :job do
  let(:team) { create(:team) }
  let(:user) { create(:user) }
  let(:session) { create(:team_chat_session, team: team) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe "hashtag action processing" do
    it "processes hashtag actions before sending to LLM" do
      agent = create(:agent, team: team)
      message = session.team_chat_messages.create!(
        sender_type: "user",
        sender_id: user.id,
        content: "#help"
      )

      allow(HashtagActions::Processor).to receive(:call).and_return(
        HashtagActions::Processor::ProcessResult.new(
          bypass_llm: true,
          response: "Available actions: #remember, #forget, #search...",
          clean_message: "",
          prompt_addons: [],
          side_effects: []
        )
      )

      TeamChatJob.perform_now(session.id, message.id)

      expect(HashtagActions::Processor).to have_received(:call)
    end

    it "strips hashtags from message when bypass_llm is false" do
      agent = create(:agent, team: team)
      message = session.team_chat_messages.create!(
        sender_type: "user",
        sender_id: user.id,
        content: "#mood cheerful Tell me a joke"
      )

      allow(HashtagActions::Processor).to receive(:call).and_return(
        HashtagActions::Processor::ProcessResult.new(
          bypass_llm: false,
          response: "Mood set to cheerful",
          clean_message: "Tell me a joke",
          prompt_addons: [ "Adjust your communication style: cheerful" ],
          side_effects: []
        )
      )

      adapter = instance_double(Providers::AnthropicAdapter)
      allow(Providers::Resolver).to receive(:call).and_return(
        double(success?: true, data: { adapter: adapter })
      )

      allow(adapter).to receive(:chat).and_return(
        double(success?: true, data: { content: "Here's a joke!", usage: {} })
      )

      TeamChatJob.perform_now(session.id, message.id)

      expect(HashtagActions::Processor).to have_received(:call)
    end

    it "bypasses LLM when hashtag action requests it" do
      agent = create(:agent, team: team)
      message = session.team_chat_messages.create!(
        sender_type: "user",
        sender_id: user.id,
        content: "#status"
      )

      allow(HashtagActions::Processor).to receive(:call).and_return(
        HashtagActions::Processor::ProcessResult.new(
          bypass_llm: true,
          response: "Agent is operational. Model: claude-3-5-sonnet",
          clean_message: "",
          prompt_addons: [],
          side_effects: []
        )
      )

      # Ensure LLM is not called
      expect(Providers::Resolver).not_to receive(:call)

      TeamChatJob.perform_now(session.id, message.id)

      # Verify response was saved to team chat
      agent_messages = session.team_chat_messages.where(sender_type: "agent")
      expect(agent_messages.count).to be >= 1
    end
  end

  describe "title generation trigger" do
    # Use bypass_llm so the agent message is saved without needing a provider stub,
    # which also means after the job runs the session has 2 messages total (user + agent).
    let!(:agent) { create(:agent, team: team, model_provider: "anthropic", llm_model: "claude-haiku-4-5", enabled: true) }
    let(:bypass_result) do
      HashtagActions::Processor::ProcessResult.new(
        bypass_llm: true,
        response: "ok",
        clean_message: "",
        prompt_addons: [],
        side_effects: []
      )
    end

    before do
      allow(HashtagActions::Processor).to receive(:call).and_return(bypass_result)
      allow(CostEstimator).to receive(:estimate).and_return(0)
    end

    it "enqueues TeamChatTitleJob after the agent loop when title is 'New Chat' and 2+ messages exist" do
      session.update!(title: "New Chat")
      message = session.team_chat_messages.create!(sender_type: "user", sender_id: user.id, content: "Hello")

      expect {
        TeamChatJob.perform_now(session.id, message.id)
      }.to have_enqueued_job(TeamChatTitleJob).with(session.id)
    end

    it "enqueues TeamChatTitleJob when title is nil and 2+ messages exist" do
      session.update!(title: nil)
      message = session.team_chat_messages.create!(sender_type: "user", sender_id: user.id, content: "Hello")

      expect {
        TeamChatJob.perform_now(session.id, message.id)
      }.to have_enqueued_job(TeamChatTitleJob).with(session.id)
    end

    it "does not enqueue TeamChatTitleJob when title is already set to a real name" do
      session.update!(title: "My Custom Chat")
      message = session.team_chat_messages.create!(sender_type: "user", sender_id: user.id, content: "Hello")

      expect {
        TeamChatJob.perform_now(session.id, message.id)
      }.not_to have_enqueued_job(TeamChatTitleJob)
    end

    it "enqueues TeamChatTitleJob only once regardless of how many agents respond" do
      # A second enabled agent means agents_to_respond.each fires twice,
      # but maybe_generate_team_chat_title runs once after the loop.
      create(:agent, team: team, model_provider: "anthropic", llm_model: "claude-haiku-4-5", enabled: true)
      session.update!(title: "New Chat")
      message = session.team_chat_messages.create!(sender_type: "user", sender_id: user.id, content: "Hello")

      expect {
        TeamChatJob.perform_now(session.id, message.id)
      }.to have_enqueued_job(TeamChatTitleJob).exactly(:once)
    end
  end

  describe "OAuth MCP path" do
    let!(:agent) { create(:agent, team: team, model_provider: "anthropic", llm_model: "claude-3-5-sonnet") }
    let!(:tool) { create(:tool, enabled: true, builtin: true) }
    let(:message) do
      session.team_chat_messages.create!(
        sender_type: "user",
        sender_id: user.id,
        content: "Hello agent"
      )
    end
    let(:hashtag_result) do
      HashtagActions::Processor::ProcessResult.new(
        bypass_llm: false, response: nil, clean_message: "Hello agent", prompt_addons: [], side_effects: []
      )
    end
    let(:channel) { "team_chat_#{session.id}" }

    before do
      allow(HashtagActions::Processor).to receive(:call).and_return(hashtag_result)
      allow(Memory::ContextBuilder).to receive(:call).and_return({ context: nil, entries: [] })
      allow(CostEstimator).to receive(:estimate).and_return(0)
      allow(Tool).to receive_message_chain(:enabled, :builtin, :to_a).and_return([ tool ])
    end

    context "when adapter uses an OAuth token" do
      let(:adapter) { double("AnthropicAdapter", is_a?: false) }

      before do
        allow(adapter).to receive(:is_a?).with(Providers::AnthropicAdapter).and_return(true)
        allow(adapter).to receive(:oauth_token?).and_return(true)
        allow(Providers::Resolver).to receive(:call).and_return(
          double(success?: true, data: { adapter: adapter })
        )
      end

      it "skips ToolLoop and streams via adapter.chat with MCP options" do
        allow(adapter).to receive(:chat) do |**opts, &block|
          expect(opts[:options]).to include(:agent_id, :session_id, :tool_definitions)
          block.call(type: "content", content: "OAuth response")
          double(success?: true, data: { content: "OAuth response", usage: {} })
        end

        expect(Agents::ToolLoop).not_to receive(:call)

        TeamChatJob.perform_now(session.id, message.id)

        expect(ActionCable.server).to have_received(:broadcast).with(
          channel, hash_including(type: "token", content: "OAuth response", agent_id: agent.id, agent_name: agent.name)
        )
      end

      it "includes tool_definitions from resolved tools" do
        allow(adapter).to receive(:chat) do |**opts, &block|
          tool_defs = opts[:options][:tool_definitions]
          expect(tool_defs).to be_an(Array)
          expect(tool_defs.first).to include(:name, :description, :input_schema)
          block.call(type: "content", content: "ok")
          double(success?: true, data: { content: "ok", usage: {} })
        end

        TeamChatJob.perform_now(session.id, message.id)
      end

      it "broadcasts tool_start and tool_result events from MCP proxy" do
        allow(adapter).to receive(:chat) do |**_opts, &block|
          block.call(type: "tool_start", tool: "web_search", input: { query: "test" })
          block.call(type: "tool_result", tool: "web_search", output: "results", success: true)
          block.call(type: "content", content: "Here are the results")
          double(success?: true, data: { content: "Here are the results", usage: {} })
        end

        TeamChatJob.perform_now(session.id, message.id)

        expect(ActionCable.server).to have_received(:broadcast).with(
          channel, hash_including(type: "tool_start", tool: "web_search", agent_id: agent.id)
        )
        expect(ActionCable.server).to have_received(:broadcast).with(
          channel, hash_including(type: "tool_result", tool: "web_search", success: true, agent_id: agent.id)
        )
      end

      it "includes load_skill in tool_definitions when agent has skills" do
        skill = create(:skill, name: "deep_research")
        agent.skills << skill

        allow(adapter).to receive(:chat) do |**opts, &block|
          tool_defs = opts[:options][:tool_definitions]
          tool_names = tool_defs.map { |t| t[:name] }
          expect(tool_names).to include("load_skill")
          block.call(type: "content", content: "ok")
          double(success?: true, data: { content: "ok", usage: {} })
        end

        TeamChatJob.perform_now(session.id, message.id)
      end

      it "saves the response to team chat messages" do
        allow(adapter).to receive(:chat) do |**_opts, &block|
          block.call(type: "content", content: "OAuth response")
          double(success?: true, data: { content: "OAuth response", usage: {} })
        end

        expect {
          TeamChatJob.perform_now(session.id, message.id)
        }.to change { session.team_chat_messages.where(sender_type: "agent").count }.by(1)

        agent_msg = session.team_chat_messages.where(sender_type: "agent").last
        expect(agent_msg.content).to eq("OAuth response")
      end
    end

    context "when adapter uses a regular API key" do
      let(:adapter) { double("AnthropicAdapter", is_a?: false) }

      before do
        allow(adapter).to receive(:is_a?).with(Providers::AnthropicAdapter).and_return(true)
        allow(adapter).to receive(:oauth_token?).and_return(false)
        allow(Providers::Resolver).to receive(:call).and_return(
          double(success?: true, data: { adapter: adapter })
        )
      end

      it "uses ToolLoop as before" do
        allow(Agents::ToolLoop).to receive(:call).and_return(
          double(success?: true, data: { content: "ToolLoop response", thinking: nil, usage: {} })
        )

        TeamChatJob.perform_now(session.id, message.id)

        expect(Agents::ToolLoop).to have_received(:call)
      end

      it "does not inject MCP options" do
        allow(Agents::ToolLoop).to receive(:call) do |**opts|
          expect(opts[:options]).not_to include(:agent_id, :session_id, :tool_definitions)
          double(success?: true, data: { content: "response", thinking: nil, usage: {} })
        end

        TeamChatJob.perform_now(session.id, message.id)
      end
    end

    context "when adapter is not AnthropicAdapter" do
      let(:adapter) { double("OtherAdapter", is_a?: false) }

      before do
        allow(Providers::Resolver).to receive(:call).and_return(
          double(success?: true, data: { adapter: adapter })
        )
      end

      it "uses ToolLoop as before" do
        allow(Agents::ToolLoop).to receive(:call).and_return(
          double(success?: true, data: { content: "ToolLoop response", thinking: nil, usage: {} })
        )

        TeamChatJob.perform_now(session.id, message.id)

        expect(Agents::ToolLoop).to have_received(:call)
      end
    end
  end

  describe "interrupt handling" do
    let!(:agent) { create(:agent, team: team) }
    let(:message) do
      session.team_chat_messages.create!(
        sender_type: "user",
        sender_id: user.id,
        content: "Do something"
      )
    end

    before do
      allow(HashtagActions::Processor).to receive(:call).and_return(
        HashtagActions::Processor::ProcessResult.new(
          bypass_llm: false,
          response: nil,
          clean_message: "Do something",
          prompt_addons: [],
          side_effects: []
        )
      )
      allow(Providers::Resolver).to receive(:call).and_return(
        double(success?: true, data: { adapter: double("adapter", is_a?: false) })
      )
    end

    context "when AgentInterrupted is raised by ToolLoop" do
      before do
        allow(Agents::ToolLoop).to receive(:call).and_raise(AgentInterrupted)
      end

      it "broadcasts cancelled event" do
        TeamChatJob.perform_now(session.id, message.id)
        expect(ActionCable.server).to have_received(:broadcast).with(
          "team_chat_#{session.id}",
          hash_including(type: "cancelled", agent_id: agent.id)
        )
      end

      it "does not broadcast an error" do
        TeamChatJob.perform_now(session.id, message.id)
        expect(ActionCable.server).not_to have_received(:broadcast).with(
          anything,
          hash_including(type: "error")
        )
      end

      it "does not save a partial message when no content was streamed" do
        expect {
          TeamChatJob.perform_now(session.id, message.id)
        }.not_to change { session.team_chat_messages.where(sender_type: "agent").count }
      end
    end

    context "when AgentInterrupted is raised after partial content was streamed via adapter.chat" do
      before do
        adapter = double("adapter")
        allow(adapter).to receive(:is_a?).with(Providers::AnthropicAdapter).and_return(false)
        allow(adapter).to receive(:chat)
          .and_yield({ type: "content", content: "partial response so far" })
          .and_raise(AgentInterrupted)
        allow(Providers::Resolver).to receive(:call).and_return(
          double(success?: true, data: { adapter: adapter })
        )
      end

      it "saves partial content with cancelled suffix" do
        TeamChatJob.perform_now(session.id, message.id)
        agent_msg = session.team_chat_messages.where(sender_type: "agent").last
        expect(agent_msg).to be_present
        expect(agent_msg.content).to include("partial response so far")
        expect(agent_msg.content).to include("_[Cancelled by user]_")
      end

      it "broadcasts cancelled event" do
        TeamChatJob.perform_now(session.id, message.id)
        expect(ActionCable.server).to have_received(:broadcast).with(
          "team_chat_#{session.id}",
          hash_including(type: "cancelled", agent_id: agent.id)
        )
      end
    end

    context "when AgentRedirected is raised by ToolLoop" do
      before do
        allow(Agents::ToolLoop).to receive(:call).and_raise(AgentRedirected.new("new direction"))
        allow(Redis.current).to receive(:get).and_return(nil)
        allow(Redis.current).to receive(:setex)
      end

      it "broadcasts redirected event with redirect message" do
        TeamChatJob.perform_now(session.id, message.id)
        expect(ActionCable.server).to have_received(:broadcast).with(
          "team_chat_#{session.id}",
          hash_including(type: "redirected", agent_id: agent.id, message: "new direction")
        )
      end

      it "creates a new user-type TeamChatMessage with the redirect content" do
        expect {
          TeamChatJob.perform_now(session.id, message.id)
        }.to change(TeamChatMessage, :count).by(1)

        redirect_msg = TeamChatMessage.last
        expect(redirect_msg.content).to eq("new direction")
        expect(redirect_msg.sender_type).to eq("user")
        expect(redirect_msg.target_agent_id).to be_nil
      end

      it "re-enqueues TeamChatJob with the redirect message" do
        expect {
          TeamChatJob.perform_now(session.id, message.id)
        }.to have_enqueued_job(TeamChatJob)
      end

      it "does not broadcast an error" do
        TeamChatJob.perform_now(session.id, message.id)
        expect(ActionCable.server).not_to have_received(:broadcast).with(
          anything,
          hash_including(type: "error")
        )
      end

      it "does not save a partial message when no content was streamed" do
        expect {
          TeamChatJob.perform_now(session.id, message.id)
        }.not_to change { session.team_chat_messages.where(sender_type: "agent").count }
      end

      context "when a second agent also receives the redirect signal" do
        before do
          allow(Redis.current).to receive(:get).and_return("1") # dedup key already set by first agent
        end

        it "does not re-enqueue a second TeamChatJob" do
          expect {
            TeamChatJob.perform_now(session.id, message.id)
          }.not_to have_enqueued_job(TeamChatJob)
        end

        it "does not create a duplicate redirect message" do
          expect {
            TeamChatJob.perform_now(session.id, message.id)
          }.not_to change { session.team_chat_messages.where(sender_type: "user").count }
        end
      end
    end

    context "when AgentRedirected is raised after partial content was streamed via adapter.chat" do
      before do
        adapter = double("adapter")
        allow(adapter).to receive(:is_a?).with(Providers::AnthropicAdapter).and_return(false)
        allow(adapter).to receive(:chat)
          .and_yield({ type: "content", content: "partial answer" })
          .and_raise(AgentRedirected.new("ignore that, do this instead"))
        allow(Providers::Resolver).to receive(:call).and_return(
          double(success?: true, data: { adapter: adapter })
        )
        allow(Redis.current).to receive(:get).and_return(nil)
        allow(Redis.current).to receive(:setex)
      end

      it "saves partial content with redirected suffix" do
        TeamChatJob.perform_now(session.id, message.id)
        agent_msg = session.team_chat_messages.where(sender_type: "agent").last
        expect(agent_msg).to be_present
        expect(agent_msg.content).to include("partial answer")
        expect(agent_msg.content).to include("_[Redirected by user]_")
      end

      it "re-enqueues TeamChatJob for the redirect" do
        expect {
          TeamChatJob.perform_now(session.id, message.id)
        }.to have_enqueued_job(TeamChatJob)
      end
    end
  end
end
