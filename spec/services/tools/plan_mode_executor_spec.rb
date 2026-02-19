# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::PlanModeExecutor do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent, metadata: {}) }
  let(:executor) { described_class.new(input: input, config: { session: session }, agent: agent) }

  describe "#call" do
    context "when action is enter" do
      let(:input) { { "action" => "enter" } }

      it "sets planning mode flag in session metadata" do
        expect { executor.call }.to change { session.reload.metadata["planning_mode"] }.to(true)
      end

      it "sets planning started timestamp" do
        executor.call
        started_at = Time.parse(session.reload.metadata["planning_started_at"])
        expect(started_at).to be_within(1.second).of(Time.current)
      end

      it "broadcasts planning mode activation" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "session_#{session.id}",
          {
            type: "planning_mode",
            planning: true,
            message: "🧠 Planning mode activated..."
          }
        )

        executor.call
      end

      it "returns success with appropriate message" do
        result = executor.call
        expect(result.success?).to be true
        expect(result.data[:output]).to eq("Planning mode activated. Tool calls will be shown in planning context.")
        expect(result.data[:exit_code]).to eq(0)
      end
    end

    context "when action is exit" do
      let(:input) { { "action" => "exit" } }

      before do
        session.update!(metadata: {
          "planning_mode" => true,
          "planning_started_at" => 1.hour.ago.iso8601
        })
      end

      it "clears planning mode flag in session metadata" do
        expect { executor.call }.to change { session.reload.metadata["planning_mode"] }.to(false)
      end

      it "sets planning ended timestamp" do
        executor.call
        ended_at = Time.parse(session.reload.metadata["planning_ended_at"])
        expect(ended_at).to be_within(1.second).of(Time.current)
      end

      it "broadcasts planning mode deactivation" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "session_#{session.id}",
          {
            type: "planning_mode",
            planning: false,
            message: "📋 Switched to implementation mode"
          }
        )

        executor.call
      end

      it "returns success with appropriate message" do
        result = executor.call
        expect(result.success?).to be true
        expect(result.data[:output]).to eq("Planning mode deactivated.")
        expect(result.data[:exit_code]).to eq(0)
      end

      context "when summary is provided" do
        let(:input) { { "action" => "exit", "summary" => "Plan to implement user authentication" } }

        it "saves the summary in session metadata" do
          executor.call
          expect(session.reload.metadata["last_planning_summary"]).to eq("Plan to implement user authentication")
        end

        it "includes summary in the broadcast" do
          expect(ActionCable.server).to receive(:broadcast).with(
            "session_#{session.id}",
            {
              type: "planning_mode",
              planning: false,
              message: "📋 Switched to implementation mode",
              summary: "Plan to implement user authentication"
            }
          )

          executor.call
        end

        it "mentions the summary in the output" do
          result = executor.call
          expect(result.data[:output]).to eq("Planning mode deactivated. Plan summary recorded.")
        end
      end
    end

    context "when action is invalid" do
      let(:input) { { "action" => "invalid" } }

      it "returns failure with error message" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to eq("Invalid action. Use 'enter' or 'exit'")
      end
    end

    context "when an exception occurs" do
      let(:input) { { "action" => "enter" } }

      before do
        allow(session).to receive(:save!).and_raise(StandardError, "Database error")
      end

      it "returns failure with error message" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to eq("Planning mode operation failed: Database error")
      end
    end
  end
end
