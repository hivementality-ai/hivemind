# frozen_string_literal: true

require "rails_helper"

RSpec.describe HeartbeatJob, type: :job do
  let(:agent) { create(:agent, name: "System Assistant", llm_model: "claude-3-5-sonnet", model_provider: "anthropic", system_agent: true) }
  let(:config) { { "enabled" => true, "interval_minutes" => 30 }.to_json }
  let(:chat_result) { double(success?: true, data: { content: "Everything looks good" }) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(Agent).to receive(:system_assistant).and_return(agent)
    allow(Setting).to receive(:get).with("heartbeat").and_return(config)
    allow(Setting).to receive(:get).with("heartbeat_last_run").and_return(nil)
    allow(Setting).to receive(:get).with("heartbeat_tasks").and_return(nil)
    allow(Setting).to receive(:set)
    allow(Sessions::Chat).to receive(:call).and_return(chat_result)
  end

  describe "#perform" do
    it "skips when config not enabled" do
      allow(Setting).to receive(:get).with("heartbeat").and_return({ "enabled" => false }.to_json)
      described_class.perform_now
      expect(Sessions::Chat).not_to have_received(:call)
    end

    it "skips when not due yet" do
      allow(Setting).to receive(:get).with("heartbeat_last_run").and_return(5.minutes.ago.iso8601)
      described_class.perform_now
      expect(Sessions::Chat).not_to have_received(:call)
    end

    it "runs when due and updates last_run" do
      described_class.perform_now
      expect(Setting).to have_received(:set).with("heartbeat_last_run", anything)
      expect(Sessions::Chat).to have_received(:call)
    end

    it "broadcasts reply via ActionCable" do
      described_class.perform_now
      expect(ActionCable.server).to have_received(:broadcast).with(
        anything,
        hash_including(type: "heartbeat", content: "Everything looks good")
      )
    end

    it "suppresses HEARTBEAT_OK responses" do
      allow(Sessions::Chat).to receive(:call).and_return(double(success?: true, data: { content: "HEARTBEAT_OK" }))
      described_class.perform_now
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it "overrides model if config specifies one and restores after" do
      config_with_model = { "enabled" => true, "interval_minutes" => 30, "model" => "gpt-4" }.to_json
      allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_model)

      described_class.perform_now

      expect(agent.reload.llm_model).to eq("claude-3-5-sonnet")
    end

    it "restores original model_provider after override" do
      config_with_model = { "enabled" => true, "interval_minutes" => 30, "model" => "gpt-4", "provider" => "openai" }.to_json
      allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_model)

      described_class.perform_now

      expect(agent.reload.model_provider).to eq("anthropic")
    end

    # ─── provider override ────────────────────────────────────────

    context "with provider stored explicitly in config" do
      let(:heartbeat_config) do
        { "enabled" => true, "interval_minutes" => 30, "model" => "claude-haiku-4-5", "provider" => "anthropic" }.to_json
      end

      before { allow(Setting).to receive(:get).with("heartbeat").and_return(heartbeat_config) }

      it "sets model_provider on the agent before calling Sessions::Chat" do
        captured_provider = nil
        allow(Sessions::Chat).to receive(:call) do |args|
          captured_provider = args[:agent].model_provider
          chat_result
        end

        described_class.perform_now

        expect(captured_provider).to eq("anthropic")
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
        captured_provider = nil
        allow(Sessions::Chat).to receive(:call) do |args|
          captured_provider = args[:agent].model_provider
          chat_result
        end

        described_class.perform_now

        expect(captured_provider).to eq("anthropic")
      end

      it "does not set provider when no ProviderConfig has the model" do
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
      expect(Sessions::Chat).to have_received(:call).with(
        hash_including(message: a_string_including("Heartbeat check-in. Time:"))
      )
    end

    it "includes checklist tasks in the prompt" do
      allow(Setting).to receive(:get).with("heartbeat_tasks").and_return([ { "task" => "Check email" } ].to_json)
      described_class.perform_now
      expect(Sessions::Chat).to have_received(:call).with(hash_including(message: a_string_including("Check email")))
    end

    it "separates standing and one-off tasks" do
      tasks = [
        { "task" => "Daily standup", "protected" => true },
        { "task" => "One-time setup", "protected" => false }
      ]
      allow(Setting).to receive(:get).with("heartbeat_tasks").and_return(tasks.to_json)
      described_class.perform_now
      prompt_arg = nil
      expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
      expect(prompt_arg).to include("Standing checks (do not remove):")
      expect(prompt_arg).to include("One-off tasks (remove after handling):")
    end

    it "does not include teammate list in the prompt" do
      team = create(:team)
      create(:agent, name: "Helper", role: "Developer", enabled: true, team: team)
      described_class.perform_now
      prompt_arg = nil
      expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
      expect(prompt_arg).not_to include("Helper")
    end

    it "does not include the task board in the prompt" do
      create(:task, title: "Deploy to staging", status: "todo", priority: "high")
      described_class.perform_now
      prompt_arg = nil
      expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
      expect(prompt_arg).not_to include("Deploy to staging")
    end

    it "includes custom prompt when set" do
      config_with_prompt = { "enabled" => true, "interval_minutes" => 30, "prompt" => "Watch for anomalies" }.to_json
      allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_prompt)
      described_class.perform_now
      expect(Sessions::Chat).to have_received(:call).with(
        hash_including(message: a_string_including("Watch for anomalies"))
      )
    end

    it "handles errors gracefully" do
      allow(Sessions::Chat).to receive(:call).and_raise(StandardError, "boom")
      expect { described_class.perform_now }.not_to raise_error
    end

    # ─── HeartbeatRun tracking ────────────────────────────────────

    it "creates a HeartbeatRun record after each execution" do
      expect { described_class.perform_now }.to change(HeartbeatRun, :count).by(1)
    end

    it "records the number of tasks in the run metadata" do
      allow(Setting).to receive(:get).with("heartbeat_tasks").and_return([ { "task" => "Do a thing" } ].to_json)
      described_class.perform_now
      run = HeartbeatRun.last
      expect(run.metadata["tasks_count"]).to eq(1)
    end

    # ─── Ephemeral sessions ──────────────────────────────────────

    it "creates a new session for each heartbeat run" do
      expect { described_class.perform_now }.to change(Session, :count).by(1)
      session = Session.last
      expect(session.title).to start_with("🫀 Heartbeat")
      expect(session.session_key).to start_with("heartbeat-")
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

    it "marks the session as completed after the run" do
      described_class.perform_now
      session = Session.last
      expect(session.status).to eq("completed")
    end

    # ─── Relay summaries ─────────────────────────────────────────

    it "includes the previous heartbeat summary in the prompt" do
      create(:heartbeat_run, agent: agent, status: "action_taken",
             summary: "Delegated Task #31 to Mando. PR #240 still in review.")

      described_class.perform_now

      prompt_arg = nil
      expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
      expect(prompt_arg).to include("Previous heartbeat handoff")
      expect(prompt_arg).to include("Delegated Task #31 to Mando")
    end

    it "does not include HEARTBEAT_OK as a relay summary" do
      create(:heartbeat_run, agent: agent, status: "ok", summary: "HEARTBEAT_OK")

      described_class.perform_now

      prompt_arg = nil
      expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
      expect(prompt_arg).not_to include("Previous heartbeat handoff")
    end

    it "stores the previous_summary on the HeartbeatRun for audit trail" do
      create(:heartbeat_run, agent: agent, status: "action_taken",
             summary: "Delegated Task #31 to Mando.")

      described_class.perform_now

      run = HeartbeatRun.last
      expect(run.previous_summary).to eq("Delegated Task #31 to Mando.")
    end

    it "includes ephemeral mode instructions in the prompt" do
      described_class.perform_now

      prompt_arg = nil
      expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
      expect(prompt_arg).to include("ephemeral mode")
      expect(prompt_arg).to include("task_manager")
      expect(prompt_arg).to include("delegate")
      expect(prompt_arg).to include("HANDOFF")
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
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: a_string_including("Heartbeat check-in. Time:"))
        )
      end

      it "does not include teammate listing" do
        create(:agent, name: "Helper", role: "Developer", enabled: true)
        described_class.perform_now
        prompt_arg = nil
        expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
        expect(prompt_arg).not_to include("Helper")
      end

      it "does not inject the open task board" do
        create(:task, title: "Should not appear", status: "todo")
        described_class.perform_now
        prompt_arg = nil
        expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
        expect(prompt_arg).not_to include("Should not appear")
      end

      it "still includes checklist tasks" do
        allow(Setting).to receive(:get).with("heartbeat_tasks").and_return([ { "task" => "Check logs" } ].to_json)
        described_class.perform_now
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: a_string_including("Check logs"))
        )
      end

      it "still includes custom prompt" do
        config_with_prompt = { "enabled" => true, "interval_minutes" => 30, "light_context" => true, "prompt" => "Watch for errors" }.to_json
        allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_prompt)
        described_class.perform_now
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: a_string_including("Watch for errors"))
        )
      end

      it "includes relay summary in light_context mode" do
        create(:heartbeat_run, agent: agent, status: "action_taken",
               summary: "Checked email, found 2 urgent items.")

        described_class.perform_now

        prompt_arg = nil
        expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
        expect(prompt_arg).to include("Previous heartbeat handoff")
        expect(prompt_arg).to include("Checked email")
      end

      it "includes ephemeral mode instructions in light_context mode" do
        described_class.perform_now

        prompt_arg = nil
        expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
        expect(prompt_arg).to include("ephemeral mode")
        expect(prompt_arg).to include("HANDOFF")
      end
    end
  end
end
