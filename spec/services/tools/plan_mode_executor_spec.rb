# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::PlanModeExecutor do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent, metadata: {}) }
  let(:executor) { described_class.new(input: input, config: { session: session }, agent: agent) }

  describe "#call" do
    context "when action is generate" do
      let(:input) { { "action" => "generate", "task" => "Build a user authentication system" } }
      let(:plan) do
        {
          "overview" => "Implement a complete authentication system",
          "context" => "Building login and signup for the web app",
          "phases" => [
            {
              "number" => 1,
              "name" => "Setup",
              "objectives" => ["Create database schema", "Setup authentication library"],
              "approach" => "Create migrations and configure gems",
              "tools_needed" => ["database", "gems"],
              "expected_output" => "Database tables and auth library configured"
            }
          ],
          "success_criteria" => ["Users can sign up", "Users can log in"],
          "estimated_duration" => "2-3 hours"
        }
      end

      before do
        allow(Agents::PlanGenerator).to receive(:call).and_return(
          ServiceResponse.success(data: { plan: plan })
        )
      end

      it "calls PlanGenerator with the agent and task" do
        expect(Agents::PlanGenerator).to receive(:call).with(
          agent: agent,
          task: "Build a user authentication system",
          session: session
        ).and_return(ServiceResponse.success(data: { plan: plan }))

        executor.call
      end

      it "stores the plan in session metadata" do
        executor.call
        expect(session.reload.metadata["current_plan"]).to eq(plan)
      end

      it "sets plan status to generated" do
        executor.call
        expect(session.reload.metadata["plan_status"]).to eq("generated")
      end

      it "initializes current phase to 0" do
        executor.call
        expect(session.reload.metadata["current_phase"]).to eq(0)
      end

      it "broadcasts the plan to the UI" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "session_#{session.id}",
          hash_including(
            type: "plan",
            action: "display",
            plan: plan
          )
        )

        executor.call
      end

      it "returns success with the plan" do
        result = executor.call
        expect(result.success?).to be true
        expect(result.data[:plan]).to eq(plan)
        expect(result.data[:output]).to include("Plan generated with 1 phases")
      end

      context "when task is missing" do
        let(:input) { { "action" => "generate" } }

        it "returns failure" do
          result = executor.call
          expect(result.success?).to be false
          expect(result.error).to eq("Task is required for plan generation")
        end
      end

      context "when plan generation fails" do
        before do
          allow(Agents::PlanGenerator).to receive(:call).and_return(
            ServiceResponse.failure(error: "LLM error")
          )
        end

        it "returns failure with the error" do
          result = executor.call
          expect(result.success?).to be false
          expect(result.error).to eq("LLM error")
        end
      end
    end

    context "when action is execute" do
      let(:input) { { "action" => "execute" } }
      let(:plan) do
        {
          "overview" => "Test plan",
          "phases" => [
            { "number" => 1, "name" => "Phase 1" },
            { "number" => 2, "name" => "Phase 2" }
          ]
        }
      end

      before do
        session.update!(metadata: { "current_plan" => plan })
      end

      it "sets plan status to executing" do
        executor.call
        expect(session.reload.metadata["plan_status"]).to eq("executing")
      end

      it "sets current phase to 1" do
        executor.call
        expect(session.reload.metadata["current_phase"]).to eq(1)
      end

      it "broadcasts execution start" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "session_#{session.id}",
          hash_including(
            type: "plan",
            action: "start_execution",
            current_phase: 1
          )
        )

        executor.call
      end

      it "returns success with phase 1 info" do
        result = executor.call
        expect(result.success?).to be true
        expect(result.data[:output]).to include("Phase 1")
      end

      context "when no plan exists" do
        before do
          session.update!(metadata: {})
        end

        it "returns failure" do
          result = executor.call
          expect(result.success?).to be false
          expect(result.error).to eq("No plan available. Generate a plan first.")
        end
      end
    end

    context "when action is update_phase" do
      let(:input) { { "action" => "update_phase", "phase_number" => 2 } }
      let(:plan) do
        {
          "phases" => [
            { "number" => 1, "name" => "Phase 1", "objectives" => ["Obj 1"] },
            { "number" => 2, "name" => "Phase 2", "objectives" => ["Obj 2"] }
          ]
        }
      end

      before do
        session.update!(metadata: { "current_plan" => plan, "current_phase" => 1 })
      end

      it "updates current phase in session metadata" do
        executor.call
        expect(session.reload.metadata["current_phase"]).to eq(2)
      end

      it "broadcasts phase update" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "session_#{session.id}",
          hash_including(
            type: "plan",
            action: "phase_update",
            current_phase: 2
          )
        )

        executor.call
      end

      it "returns success with phase info" do
        result = executor.call
        expect(result.success?).to be true
        expect(result.data[:output]).to include("Phase 2")
      end

      context "when phase number is out of range" do
        let(:input) { { "action" => "update_phase", "phase_number" => 99 } }

        it "returns failure" do
          result = executor.call
          expect(result.success?).to be false
          expect(result.error).to include("Invalid phase number")
        end
      end

      context "when no plan exists" do
        before do
          session.update!(metadata: {})
        end

        it "returns failure" do
          result = executor.call
          expect(result.success?).to be false
          expect(result.error).to eq("No plan available")
        end
      end
    end

    context "when action is invalid" do
      let(:input) { { "action" => "invalid" } }

      it "returns failure with error message" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to include("Invalid action")
      end
    end

    context "when an exception occurs" do
      let(:input) { { "action" => "generate", "task" => "Test task" } }

      before do
        allow(Agents::PlanGenerator).to receive(:call).and_raise(StandardError, "Unexpected error")
      end

      it "returns failure with error message" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to include("Planning mode operation failed")
      end
    end
  end

  describe "#call with exit action" do
    let(:plan) do
      {
        "phases" => [
          { "number" => 1, "name" => "Phase 1" }
        ]
      }
    end

    before do
      session.update!(metadata: { "current_plan" => plan, "current_phase" => 1 })
    end

    context "when action is exit" do
      let(:input) { { "action" => "exit" } }

      before do
        allow(Agents::PlanSummaryGenerator).to receive(:call).and_return(
          ServiceResponse.success(data: {
            summary: {
              "original_task" => "Test task",
              "phases_completed" => 1,
              "total_phases" => 1,
              "duration" => "1 hour",
              "key_results" => ["Result 1"]
            },
            markdown: "# Plan Summary",
            learnings: ["Learning 1"]
          })
        )
      end

      it "calls PlanSummaryGenerator" do
        expect(Agents::PlanSummaryGenerator).to receive(:call).with(
          session: session,
          agent: agent
        ).and_return(ServiceResponse.success(data: {
          summary: { "original_task" => "Test" },
          markdown: "# Plan",
          learnings: []
        }))

        executor.call
      end

      it "sets plan status to completed" do
        executor.call
        expect(session.reload.metadata["plan_status"]).to eq("completed")
      end

      it "stores plan summary in metadata" do
        executor.call
        summary = session.reload.metadata["plan_summary"]

        expect(summary).to have_key("original_task")
        expect(summary).to have_key("phases_completed")
        expect(summary).to have_key("total_phases")
      end

      it "broadcasts plan exit to UI" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "session_#{session.id}",
          hash_including(
            type: "plan",
            action: "exit"
          )
        )

        executor.call
      end

      it "returns success with summary and markdown" do
        result = executor.call

        expect(result.success?).to be true
        expect(result.data).to have_key(:summary)
        expect(result.data).to have_key(:markdown)
      end

      context "when no plan exists" do
        before { session.update!(metadata: {}) }

        it "returns failure" do
          result = executor.call
          expect(result.success?).to be false
          expect(result.error).to eq("No active plan to exit")
        end
      end

      context "when summary generation fails" do
        before do
          allow(Agents::PlanSummaryGenerator).to receive(:call).and_return(
            ServiceResponse.failure(error: "Generation failed")
          )
        end

        it "returns failure with error" do
          result = executor.call
          expect(result.success?).to be false
          expect(result.error).to eq("Generation failed")
        end
      end
    end
  end
end
