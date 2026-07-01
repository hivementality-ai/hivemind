# frozen_string_literal: true

require "rails_helper"

RSpec.describe HeartbeatJob, type: :job do
  let(:agent) { create(:agent, name: "System Assistant", llm_model: "claude-3-5-sonnet", model_provider: "anthropic", system_agent: true) }
  let(:config) { { "enabled" => true, "interval_minutes" => 30 }.to_json }

  before do
    allow(Agent).to receive(:system_assistant).and_return(agent)
    allow(Setting).to receive(:get).with("heartbeat").and_return(config)
    allow(Setting).to receive(:get).with("heartbeat_last_run").and_return(nil)
    allow(Setting).to receive(:get).with("heartbeat_tasks").and_return(nil)
    allow(Setting).to receive(:set)
    # HeartbeatJob dispatches the actual LLM work asynchronously; HeartbeatRun
    # tracking, memory overwrite, model restore, and broadcasting all happen in
    # ChatStreamJob#finalize_heartbeat_session (covered in chat_stream_job_spec).
    allow(ChatStreamJob).to receive(:perform_later)
  end

  # The prompt is the 2nd positional arg to ChatStreamJob.perform_later(session_id, prompt, attachments).
  def dispatched_prompt
    prompt = nil
    expect(ChatStreamJob).to have_received(:perform_later) { |_id, p, _att| prompt = p }
    prompt
  end

  describe "#perform" do
    it "skips when config not enabled" do
      allow(Setting).to receive(:get).with("heartbeat").and_return({ "enabled" => false }.to_json)
      described_class.perform_now
      expect(ChatStreamJob).not_to have_received(:perform_later)
    end

    it "skips when not due yet" do
      allow(Setting).to receive(:get).with("heartbeat_last_run").and_return(5.minutes.ago.iso8601)
      described_class.perform_now
      expect(ChatStreamJob).not_to have_received(:perform_later)
    end

    it "runs when due, updates last_run, and dispatches ChatStreamJob" do
      described_class.perform_now
      expect(Setting).to have_received(:set).with("heartbeat_last_run", anything)
      expect(ChatStreamJob).to have_received(:perform_later)
    end

    it "handles errors gracefully" do
      allow(ChatStreamJob).to receive(:perform_later).and_raise(StandardError, "boom")
      expect { described_class.perform_now }.not_to raise_error
    end

    # ─── Model / provider override (applied before dispatch) ──────

    it "overrides the agent model when config specifies one" do
      config_with_model = { "enabled" => true, "interval_minutes" => 30, "model" => "gpt-4" }.to_json
      allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_model)

      described_class.perform_now

      expect(agent.reload.llm_model).to eq("gpt-4")
    end

    it "stores the original model and provider in session metadata for later restore" do
      config_with_model = { "enabled" => true, "interval_minutes" => 30, "model" => "gpt-4" }.to_json
      allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_model)

      described_class.perform_now

      meta = Session.last.metadata
      expect(meta["original_model"]).to eq("claude-3-5-sonnet")
      expect(meta["original_provider"]).to eq("anthropic")
      expect(meta["heartbeat_model"]).to eq("gpt-4")
    end

    context "with provider stored explicitly in config" do
      let(:heartbeat_config) do
        { "enabled" => true, "interval_minutes" => 30, "model" => "claude-haiku-4-5", "provider" => "openai" }.to_json
      end

      before { allow(Setting).to receive(:get).with("heartbeat").and_return(heartbeat_config) }

      it "sets model_provider on the agent before dispatch" do
        described_class.perform_now
        expect(agent.reload.model_provider).to eq("openai")
      end
    end

    context "without provider in config — derives from ProviderConfig" do
      let!(:anthropic_config) do
        create(:provider_config,
               name: "Anthropic",
               adapter_type: "anthropic",
               enabled: true,
               model_definitions: [ { "id" => "claude-haiku-4-5" } ])
      end

      let(:heartbeat_config) do
        { "enabled" => true, "interval_minutes" => 30, "model" => "claude-haiku-4-5" }.to_json
      end

      before { allow(Setting).to receive(:get).with("heartbeat").and_return(heartbeat_config) }

      it "derives provider from ProviderConfig model_definitions" do
        agent.update_column(:model_provider, "openai")

        described_class.perform_now

        expect(agent.reload.model_provider).to eq("anthropic")
      end

      it "does not change provider when no ProviderConfig has the model" do
        agent.update_column(:model_provider, "anthropic")
        unknown_config = { "enabled" => true, "interval_minutes" => 30, "model" => "unknown-model-xyz" }.to_json
        allow(Setting).to receive(:get).with("heartbeat").and_return(unknown_config)

        described_class.perform_now

        expect(agent.reload.model_provider).to eq("anthropic")
      end
    end

    # ─── Prompt content ───────────────────────────────────────────

    it "includes a timestamp in the prompt" do
      described_class.perform_now
      expect(dispatched_prompt).to include("Heartbeat check-in. Time:")
    end

    it "includes checklist tasks in the prompt" do
      allow(Setting).to receive(:get).with("heartbeat_tasks").and_return([ { "task" => "Check email" } ].to_json)
      described_class.perform_now
      expect(dispatched_prompt).to include("Check email")
    end

    it "separates standing and one-off tasks" do
      tasks = [
        { "task" => "Daily standup", "protected" => true },
        { "task" => "One-time setup", "protected" => false }
      ]
      allow(Setting).to receive(:get).with("heartbeat_tasks").and_return(tasks.to_json)
      described_class.perform_now
      prompt = dispatched_prompt
      expect(prompt).to include("Standing checks (do not remove):")
      expect(prompt).to include("One-off tasks (remove after handling):")
    end

    it "does not include teammate list in the prompt" do
      team = create(:team)
      create(:agent, name: "Helper", role: "Developer", enabled: true, team: team)
      described_class.perform_now
      expect(dispatched_prompt).not_to include("Helper")
    end

    it "does not include the task board in the prompt" do
      create(:task, title: "Deploy to staging", status: "todo", priority: "high")
      described_class.perform_now
      expect(dispatched_prompt).not_to include("Deploy to staging")
    end

    it "includes custom prompt when set" do
      config_with_prompt = { "enabled" => true, "interval_minutes" => 30, "prompt" => "Watch for anomalies" }.to_json
      allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_prompt)
      described_class.perform_now
      expect(dispatched_prompt).to include("Watch for anomalies")
    end

    # ─── Tool enforcement in prompt ───────────────────────────────

    it "includes tool enforcement instructions in the prompt" do
      described_class.perform_now
      prompt = dispatched_prompt
      expect(prompt).to include("NEVER fabricate or invent tool results")
      expect(prompt).to include("MUST use them")
      expect(prompt).to include("task_manager")
    end

    it "explicitly forbids Trello in the prompt" do
      described_class.perform_now
      prompt = dispatched_prompt
      expect(prompt).to include("FORBIDDEN TOOLS")
      expect(prompt).to include("trello")
      expect(prompt).to include("do NOT use Trello")
    end

    it "lists allowed tools in the prompt" do
      described_class.perform_now
      prompt = dispatched_prompt
      expect(prompt).to include("ALLOWED TOOLS")
      expect(prompt).to include("task_manager")
      expect(prompt).to include("delegate")
      expect(prompt).to include("memory_search")
      expect(prompt).to include("heartbeat_write")
    end

    it "instructs not to ask the user questions" do
      described_class.perform_now
      expect(dispatched_prompt).to include("Do NOT ask the user questions")
    end

    it "includes ephemeral mode instructions in the prompt" do
      described_class.perform_now
      prompt = dispatched_prompt
      expect(prompt).to include("ephemeral mode")
      expect(prompt).to include("task_manager")
      expect(prompt).to include("delegate")
      expect(prompt).to include("HANDOFF")
    end

    # ─── Relay summaries ─────────────────────────────────────────

    it "includes the previous heartbeat summary in the prompt" do
      create(:heartbeat_run, agent: agent, status: "action_taken",
             summary: "Delegated Task #31 to Mando. PR #240 still in review.")

      described_class.perform_now

      prompt = dispatched_prompt
      expect(prompt).to include("Previous heartbeat handoff")
      expect(prompt).to include("Delegated Task #31 to Mando")
    end

    it "does not include HEARTBEAT_OK as a relay summary" do
      create(:heartbeat_run, agent: agent, status: "ok", summary: "HEARTBEAT_OK")

      described_class.perform_now

      expect(dispatched_prompt).not_to include("Previous heartbeat handoff")
    end

    it "stores the previous_summary in session metadata for the audit trail" do
      create(:heartbeat_run, agent: agent, status: "action_taken",
             summary: "Delegated Task #31 to Mando.")

      described_class.perform_now

      expect(Session.last.metadata["previous_summary"]).to eq("Delegated Task #31 to Mando.")
    end

    # ─── Ephemeral sessions ──────────────────────────────────────

    it "creates a new session for each heartbeat run" do
      expect { described_class.perform_now }.to change(Session, :count).by(1)
      session = Session.last
      expect(session.title).to start_with("🫀 Heartbeat")
      expect(session.session_key).to start_with("heartbeat-")
      expect(session.metadata["type"]).to eq("heartbeat")
    end

    it "creates a unique session each time (no reuse)" do
      described_class.perform_now
      allow(Setting).to receive(:get).with("heartbeat_last_run").and_return(nil)
      first_session = Session.last

      described_class.perform_now
      second_session = Session.last

      expect(first_session.id).not_to eq(second_session.id)
      expect(first_session.session_key).not_to eq(second_session.session_key)
    end

    it "records the number of tasks in the session metadata" do
      allow(Setting).to receive(:get).with("heartbeat_tasks").and_return([ { "task" => "Do a thing" } ].to_json)
      described_class.perform_now
      expect(Session.last.metadata["tasks_count"]).to eq(1)
    end

    # ─── Session cleanup ─────────────────────────────────────────

    it "cleans up completed heartbeat sessions older than 24 hours" do
      old_session = create(:session, agent: agent, title: "🫀 Heartbeat 08:00",
                           status: "completed", created_at: 25.hours.ago)
      recent_session = create(:session, agent: agent, title: "🫀 Heartbeat 09:00",
                              status: "completed", created_at: 1.hour.ago)

      described_class.perform_now

      expect(Session.exists?(old_session.id)).to be false
      expect(Session.exists?(recent_session.id)).to be true
    end

    it "does not delete non-heartbeat sessions" do
      other_session = create(:session, agent: agent, title: "Regular chat",
                             status: "completed", created_at: 25.hours.ago)

      described_class.perform_now

      expect(Session.exists?(other_session.id)).to be true
    end

    # ─── light_context mode ───────────────────────────────────────

    context "with light_context enabled" do
      let(:config) { { "enabled" => true, "interval_minutes" => 30, "light_context" => true }.to_json }

      it "includes a timestamp in the minimal prompt" do
        described_class.perform_now
        expect(dispatched_prompt).to include("Heartbeat check-in. Time:")
      end

      it "does not include teammate listing" do
        create(:agent, name: "Helper", role: "Developer", enabled: true)
        described_class.perform_now
        expect(dispatched_prompt).not_to include("Helper")
      end

      it "does not inject the open task board" do
        create(:task, title: "Should not appear", status: "todo")
        described_class.perform_now
        expect(dispatched_prompt).not_to include("Should not appear")
      end

      it "still includes checklist tasks" do
        allow(Setting).to receive(:get).with("heartbeat_tasks").and_return([ { "task" => "Check logs" } ].to_json)
        described_class.perform_now
        expect(dispatched_prompt).to include("Check logs")
      end

      it "still includes custom prompt" do
        config_with_prompt = { "enabled" => true, "interval_minutes" => 30, "light_context" => true, "prompt" => "Watch for errors" }.to_json
        allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_prompt)
        described_class.perform_now
        expect(dispatched_prompt).to include("Watch for errors")
      end

      it "includes relay summary in light_context mode" do
        create(:heartbeat_run, agent: agent, status: "action_taken",
               summary: "Checked email, found 2 urgent items.")

        described_class.perform_now

        prompt = dispatched_prompt
        expect(prompt).to include("Previous heartbeat handoff")
        expect(prompt).to include("Checked email")
      end

      it "includes tool enforcement instructions in light_context mode" do
        described_class.perform_now
        prompt = dispatched_prompt
        expect(prompt).to include("NEVER fabricate")
        expect(prompt).to include("MUST use them")
      end
    end
  end
end
