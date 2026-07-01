# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatStreamJob, type: :job do
  let(:agent) { create(:agent, model_provider: "anthropic", llm_model: "claude-3-5-sonnet") }
  let(:session) { create(:session, agent: agent, transcript: []) }
  let(:channel) { "session_#{session.id}" }
  let(:adapter) { instance_double("Providers::AnthropicAdapter") }
  let(:resolver_result) { double(success?: true, data: { adapter: adapter }) }
  let(:hashtag_bypass_false) do
    HashtagActions::Processor::ProcessResult.new(
      bypass_llm: false, response: nil, clean_message: "Hello", prompt_addons: [], side_effects: []
    )
  end
  let(:context_manager) { instance_double(Agents::ContextManager, prune_messages: [ { role: "system", content: "sys" }, { role: "user", content: "Hello" } ]) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(HashtagActions::Processor).to receive(:call).and_return(hashtag_bypass_false)
    allow(Providers::Resolver).to receive(:call).and_return(resolver_result)
    allow(Agents::ContextManager).to receive(:new).and_return(context_manager)
    allow(CostEstimator).to receive(:estimate).and_return(5)

    # Stub memory system (avoids Ollama HTTP calls)
    allow(Memory::ContextBuilder).to receive(:call).and_return({ context: nil, entries: [] })
    allow(Memory::Embedding).to receive(:generate).and_return(nil)

    # Stub origin delivery (called via PostProcessor)
    allow(Channels::OriginDelivery).to receive(:call)
  end

  describe "#perform" do
    context "hashtag bypass" do
      let(:hashtag_bypass) do
        HashtagActions::Processor::ProcessResult.new(
          bypass_llm: true, response: "Bypassed!", clean_message: "", prompt_addons: [], side_effects: []
        )
      end

      before { allow(HashtagActions::Processor).to receive(:call).and_return(hashtag_bypass) }

      it "broadcasts response and returns without calling LLM" do
        described_class.perform_now(session.id, "#help")

        expect(Providers::Resolver).not_to have_received(:call)
        expect(ActionCable.server).to have_received(:broadcast).with(channel, hash_including(type: "done", content: "Bypassed!"))
      end

      it "appends user and assistant transcript entries" do
        described_class.perform_now(session.id, "#help")
        session.reload
        expect(session.transcript.size).to eq(2)
        expect(session.transcript.last["role"]).to eq("assistant")
      end
    end

    context "normal chat flow (no tools)" do
      before do
        allow(adapter).to receive(:chat) do |**_opts, &block|
          block.call(type: "content", content: "Hi there!")
          double(success?: true, data: { content: "Hi there!", usage: { input_tokens: 10, output_tokens: 5 } })
        end
      end

      it "resolves provider and streams response" do
        described_class.perform_now(session.id, "Hello")

        expect(Providers::Resolver).to have_received(:call).with(hash_including(provider_name: "anthropic"))
        expect(ActionCable.server).to have_received(:broadcast).with(channel, hash_including(type: "token", content: "Hi there!"))
        expect(ActionCable.server).to have_received(:broadcast).with(channel, hash_including(type: "done"))
      end

      it "creates a UsageRecord" do
        expect { described_class.perform_now(session.id, "Hello") }.to change(UsageRecord, :count).by(1)
      end

      it "enqueues MemoryExtractionJob for messages >= 50 chars" do
        expect { described_class.perform_now(session.id, "This is a long enough message to store in memory for the agent") }.to have_enqueued_job(MemoryExtractionJob)
      end

      it "does not enqueue MemoryExtractionJob for short messages" do
        expect { described_class.perform_now(session.id, "Hi") }.not_to have_enqueued_job(MemoryExtractionJob)
      end

      it "prunes messages via ContextManager" do
        described_class.perform_now(session.id, "Hello")
        expect(context_manager).to have_received(:prune_messages)
      end
    end

    context "done broadcast always includes content for UI fallback" do
      it "includes full content in done broadcast after streaming" do
        allow(adapter).to receive(:chat) do |**_opts, &block|
          block.call(type: "content", content: "Hello!")
          double(success?: true, data: { content: "Hello!", usage: { input_tokens: 10, output_tokens: 5 } })
        end

        described_class.perform_now(session.id, "Hello")

        expect(ActionCable.server).to have_received(:broadcast).with(
          channel, hash_including(type: "done", content: "Hello!")
        )
      end

      it "includes full content in done broadcast via hashtag bypass" do
        allow(HashtagActions::Processor).to receive(:call).and_return(
          HashtagActions::Processor::ProcessResult.new(
            bypass_llm: true, response: "Help info", clean_message: "", prompt_addons: [], side_effects: []
          )
        )

        described_class.perform_now(session.id, "#help")

        expect(ActionCable.server).to have_received(:broadcast).with(
          channel, hash_including(type: "done", content: "Help info")
        )
      end
    end

    context "with tool-equipped agent" do
      let(:tool) { create(:tool, enabled: true, builtin: true) }
      let(:tool_result) { double(success?: true, data: { content: "Tool result", thinking: nil, usage: {} }) }

      before do
        allow(Tool).to receive_message_chain(:enabled, :builtin, :to_a).and_return([ tool ])
        allow(Agents::ToolLoop).to receive(:call).and_return(tool_result)
      end

      it "calls ToolLoop when tools are available" do
        described_class.perform_now(session.id, "Hello")
        expect(Agents::ToolLoop).to have_received(:call)
      end
    end

    context "thinking support" do
      let(:agent) { create(:agent, model_provider: "anthropic", llm_model: "claude-3-5-sonnet", thinking_enabled: true, thinking_budget_tokens: 5000, thinking_visibility: "debug") }

      before do
        allow(adapter).to receive(:chat) do |**_opts, &block|
          block.call(type: "thinking_start")
          block.call(type: "thinking", content: "Let me think...")
          block.call(type: "thinking_stop")
          block.call(type: "content", content: "Answer")
          double(success?: true, data: { content: "Answer", usage: {} })
        end
      end

      it "broadcasts thinking chunks when thinking_visibility is debug" do
        described_class.perform_now(session.id, "Hello")
        expect(ActionCable.server).to have_received(:broadcast).with(channel, { type: "thinking_start" })
        expect(ActionCable.server).to have_received(:broadcast).with(channel, { type: "thinking", content: "Let me think..." })
        expect(ActionCable.server).to have_received(:broadcast).with(channel, { type: "thinking_stop" })
      end
    end

    context "error handling" do
      before do
        allow(adapter).to receive(:chat).and_raise(StandardError, "LLM exploded")
        # Ensure no tools so it goes to the non-tool path
        allow(Tool).to receive_message_chain(:enabled, :builtin, :to_a).and_return([])
        agent.agent_tools.destroy_all if agent.respond_to?(:agent_tools)
      end

      it "broadcasts error on exception" do
        described_class.perform_now(session.id, "Hello")
        expect(ActionCable.server).to have_received(:broadcast).with(channel, hash_including(type: "error", content: "Error: LLM exploded"))
      end
    end

    context "provider resolution failure" do
      let(:resolver_result) { double(success?: false, error: "No provider found") }

      it "broadcasts error and returns" do
        described_class.perform_now(session.id, "Hello")
        expect(ActionCable.server).to have_received(:broadcast).with(channel, hash_including(type: "error", content: "No provider found"))
      end
    end

    context "with image attachments" do
      let(:attachment) do
        att = create(:chat_attachment, session: session, content_type: "image/png", filename: "photo.png")
        allow(att).to receive(:image?).and_return(true)
        allow(att).to receive(:document?).and_return(false)
        blob = double("blob", signed_id: "abc123")
        allow(att).to receive(:file).and_return(double(attached?: true, blob: blob))
        allow(att).to receive(:to_base64).and_return("base64data")
        allow(att).to receive(:media_type).and_return("image/png")
        allow(att).to receive(:update)
        att
      end

      before do
        allow_any_instance_of(described_class).to receive(:rails_blob_url).and_return("/blob/test")
        allow(ChatAttachment).to receive(:where).and_return([ attachment ])
        allow(adapter).to receive(:chat).and_return(double(success?: true, data: { content: "I see an image", usage: {} }))
      end

      it "builds vision message for image attachments" do
        described_class.perform_now(session.id, "What is this?", [ attachment.id ])
        session.reload
        expect(session.transcript.first["images"]).to be_present
      end
    end

    context "with document attachments" do
      let(:doc_attachment) do
        att = create(:chat_attachment, session: session, content_type: "application/pdf", filename: "doc.pdf", byte_size: 2048)
        allow(att).to receive(:image?).and_return(false)
        allow(att).to receive(:document?).and_return(true)
        allow(att).to receive(:file).and_return(double(attached?: true, download: "file content"))
        att
      end

      before do
        allow(ChatAttachment).to receive(:where).and_return(double(to_a: [ doc_attachment ]).tap { |d|
          allow(d).to receive(:select) { |&block| [ doc_attachment ].select(&block) }
        })
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:binwrite)
        allow(adapter).to receive(:chat).and_return(double(success?: true, data: { content: "I read the doc", usage: {} }))
      end

      it "saves docs to workspace and appends file info to message" do
        described_class.perform_now(session.id, "Read this doc", [ doc_attachment.id ])
        expect(File).to have_received(:binwrite)
      end
    end
  end

  # Heartbeat finalization moved here from HeartbeatJob: when an ephemeral
  # heartbeat session completes, ChatStreamJob's ensure block records the
  # HeartbeatRun, restores the system assistant's model/provider, overwrites
  # its single memory, and broadcasts any action taken.
  describe "#finalize_heartbeat_session" do
    let(:hb_agent) do
      create(:agent, name: "System Assistant", llm_model: "claude-3-5-sonnet",
             model_provider: "anthropic", system_agent: true)
    end
    let(:job) { described_class.new }

    def heartbeat_session(meta = {})
      base = {
        "type" => "heartbeat",
        "heartbeat_model" => "claude-3-5-sonnet",
        "tasks_count" => 0,
        "started_at" => Time.current.iso8601
      }
      create(:session, agent: hb_agent, status: "active",
             session_key: "heartbeat-#{SecureRandom.hex(4)}",
             title: "🫀 Heartbeat", metadata: base.merge(meta))
    end

    def finalize(session, reply, tool_history = [])
      job.send(:finalize_heartbeat_session, session, reply, tool_history)
    end

    it "creates a HeartbeatRun record" do
      session = heartbeat_session
      expect { finalize(session, "Did some work", [ { tool: "task_manager" } ]) }
        .to change(HeartbeatRun, :count).by(1)
    end

    it "marks the session as completed" do
      session = heartbeat_session
      finalize(session, "Did some work")
      expect(session.reload.status).to eq("completed")
    end

    it "records tasks_count in the run metadata" do
      session = heartbeat_session("tasks_count" => 3)
      finalize(session, "Did some work")
      expect(HeartbeatRun.last.metadata["tasks_count"]).to eq(3)
    end

    it "records tool_calls_count in the run metadata" do
      session = heartbeat_session
      finalize(session, "Checked the board", [ { tool: "task_manager", input: { action: "list" } } ])
      expect(HeartbeatRun.last.metadata["tool_calls_count"]).to eq(1)
    end

    it "logs a warning when zero tool calls are made" do
      session = heartbeat_session
      expect(Rails.logger).to receive(:warn).with(/ZERO tool calls/)
      finalize(session, "Everything fine", [])
    end

    it "stores the previous_summary on the HeartbeatRun for audit trail" do
      session = heartbeat_session("previous_summary" => "Delegated Task #31 to Mando.")
      finalize(session, "Did some work")
      expect(HeartbeatRun.last.previous_summary).to eq("Delegated Task #31 to Mando.")
    end

    it "records action_taken status for a substantive reply" do
      session = heartbeat_session
      finalize(session, "Delegated a task")
      expect(HeartbeatRun.last.status).to eq("action_taken")
    end

    it "records ok status for a HEARTBEAT_OK reply" do
      session = heartbeat_session
      finalize(session, "HEARTBEAT_OK")
      expect(HeartbeatRun.last.status).to eq("ok")
    end

    it "restores the original model and provider after the run" do
      hb_agent.update_columns(llm_model: "gpt-4", model_provider: "openai")
      session = heartbeat_session("original_model" => "claude-3-5-sonnet", "original_provider" => "anthropic")

      finalize(session, "Did some work")

      expect(hb_agent.reload.llm_model).to eq("claude-3-5-sonnet")
      expect(hb_agent.reload.model_provider).to eq("anthropic")
    end

    it "broadcasts the reply when action was taken" do
      session = heartbeat_session
      finalize(session, "Everything looks good")
      expect(ActionCable.server).to have_received(:broadcast).with(
        "session_#{session.session_key}",
        hash_including(type: "heartbeat", content: "Everything looks good")
      )
    end

    it "suppresses the broadcast for HEARTBEAT_OK replies" do
      session = heartbeat_session
      finalize(session, "HEARTBEAT_OK")
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it "overwrites the system assistant memory with the latest summary" do
      create(:memory_entry, agent: hb_agent, content: "old heartbeat memory")
      session = heartbeat_session

      finalize(session, "Everything looks good")

      memories = hb_agent.memory_entries.reload
      expect(memories.count).to eq(1)
      expect(memories.first.content).to eq("Everything looks good")
      expect(memories.first.memory_type).to eq("semantic")
      expect(memories.first.importance).to eq(1.0)
      expect(memories.first.metadata["source"]).to eq("heartbeat")
    end

    it "replaces multiple old memories with a single new one" do
      create(:memory_entry, agent: hb_agent, content: "old memory 1")
      create(:memory_entry, agent: hb_agent, content: "old memory 2")
      create(:memory_entry, agent: hb_agent, content: "old memory 3")
      session = heartbeat_session

      finalize(session, "Fresh summary")

      expect(hb_agent.memory_entries.reload.count).to eq(1)
    end

    it "does not create a memory when the reply is blank" do
      session = heartbeat_session
      finalize(session, "")
      expect(hb_agent.memory_entries.count).to eq(0)
    end

    it "does not affect other agents' memories" do
      other_agent = create(:agent, name: "Other")
      other_memory = create(:memory_entry, agent: other_agent, content: "should survive")
      session = heartbeat_session

      finalize(session, "Did some work")

      expect(other_agent.memory_entries.reload.count).to eq(1)
      expect(other_memory.reload.content).to eq("should survive")
    end
  end
end
