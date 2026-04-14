# frozen_string_literal: true

require "rails_helper"

RSpec.describe HeartbeatJob, type: :job do
  let(:agent) { create(:agent, name: "System Assistant", llm_model: "claude-3-5-sonnet", system_agent: true) }
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

    it "builds prompt with checklist tasks" do
      allow(Setting).to receive(:get).with("heartbeat_tasks").and_return([ { "task" => "Check email" } ].to_json)
      described_class.perform_now
      expect(Sessions::Chat).to have_received(:call).with(hash_including(message: a_string_including("Check email")))
    end

    it "includes teammates in prompt" do
      create(:agent, name: "Helper", role: "Developer", enabled: true)
      described_class.perform_now
      expect(Sessions::Chat).to have_received(:call).with(hash_including(message: a_string_including("Helper")))
    end

    it "handles errors gracefully" do
      allow(Sessions::Chat).to receive(:call).and_raise(StandardError, "boom")
      expect { described_class.perform_now }.not_to raise_error
    end

    # ─── Open task board injection ────────────────────────────────

    context "with open tasks on the board" do
      let!(:open_task) { create(:task, title: "Deploy to staging", status: "todo", priority: "high") }
      let!(:done_task) { create(:task, title: "Already shipped", status: "done") }

      it "injects open tasks into the full prompt" do
        described_class.perform_now
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: a_string_including("Deploy to staging"))
        )
      end

      it "does not include done tasks in the prompt" do
        described_class.perform_now
        prompt_arg = nil
        expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
        expect(prompt_arg).not_to include("Already shipped")
      end

      it "includes the task_manager tool hint in the prompt" do
        described_class.perform_now
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: a_string_including("task_manager"))
        )
      end

      it "limits the injected task list to 20 tasks" do
        create_list(:task, 25, status: "todo")
        described_class.perform_now
        prompt_arg = nil
        expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
        # Count to_summary lines — each starts with [#
        task_lines = prompt_arg.scan(/\[#\d+\]/).size
        expect(task_lines).to be <= 20
      end
    end

    context "when there are no open tasks" do
      before { Task.delete_all }

      it "does not inject a task section into the prompt" do
        described_class.perform_now
        prompt_arg = nil
        expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
        expect(prompt_arg).not_to include("Open tasks on the team board")
      end
    end

    # ─── Overdue callout ─────────────────────────────────────────

    context "with overdue tasks" do
      let!(:overdue_task) do
        create(:task, :overdue, title: "Fix the memory leak")
      end

      it "adds an overdue callout section to the prompt" do
        described_class.perform_now
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: a_string_including("Overdue tasks requiring attention"))
        )
      end

      it "includes the overdue task in the callout" do
        described_class.perform_now
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: a_string_including("Fix the memory leak"))
        )
      end
    end

    context "with no overdue tasks" do
      let!(:future_task) { create(:task, status: "todo", due_at: 7.days.from_now) }

      it "does not add an overdue section" do
        described_class.perform_now
        prompt_arg = nil
        expect(Sessions::Chat).to have_received(:call) { |args| prompt_arg = args[:message] }
        expect(prompt_arg).not_to include("Overdue tasks requiring attention")
      end
    end

    # ─── HeartbeatRun tracking ────────────────────────────────────

    it "creates a HeartbeatRun record after each execution" do
      expect { described_class.perform_now }.to change(HeartbeatRun, :count).by(1)
    end

    it "records the number of open tasks in the run metadata" do
      create_list(:task, 3, status: "todo")
      described_class.perform_now
      run = HeartbeatRun.last
      expect(run.metadata["tasks_count"]).to be_a(Integer)
    end

    # ─── light_context mode ───────────────────────────────────────

    context "with light_context enabled" do
      let(:config) { { "enabled" => true, "interval_minutes" => 30, "light_context" => true }.to_json }

      it "uses a minimal prompt" do
        described_class.perform_now
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: a_string_including("Heartbeat check-in. Tools:"))
        )
      end

      it "does not include teammate listing" do
        create(:agent, name: "Helper", role: "Developer", enabled: true)
        described_class.perform_now
        call_args = nil
        expect(Sessions::Chat).to have_received(:call) { |args| call_args = args }
        expect(call_args[:message]).not_to include("Available teammates")
      end

      it "does not inject the open task board" do
        create(:task, title: "Should not appear", status: "todo")
        described_class.perform_now
        call_args = nil
        expect(Sessions::Chat).to have_received(:call) { |args| call_args = args }
        expect(call_args[:message]).not_to include("Open tasks on the team board")
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
    end
  end
end
