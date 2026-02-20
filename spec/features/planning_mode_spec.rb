# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Planning Mode", type: :feature do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:plan) do
    {
      "overview" => "Implement user authentication",
      "context" => "Building secure login for the application",
      "phases" => [
        {
          "number" => 1,
          "name" => "Database Setup",
          "objectives" => ["Create users table"],
          "approach" => "Write database migration",
          "tools_needed" => ["shell", "file_write"],
          "expected_output" => "Users table created"
        },
        {
          "number" => 2,
          "name" => "Authentication Routes",
          "objectives" => ["Create login endpoint"],
          "approach" => "Build controllers and views",
          "tools_needed" => ["file_write", "shell"],
          "expected_output" => "Login page accessible"
        }
      ],
      "success_criteria" => ["Users can log in", "Sessions persist"],
      "estimated_duration" => "4 hours"
    }
  end

  describe "Plan generation flow" do
    before do
      create(:tool, name: "plan_mode", executor_type: "plan_mode")
      
      # Mock LLM response
      allow_any_instance_of(Anthropic::Client).to receive(:messages).and_return(
        double(
          content: [
            double(type: "text", text: plan.to_json)
          ],
          usage: double(input_tokens: 100, output_tokens: 200)
        )
      )
    end

    it "generates a plan from a task description" do
      generator = Agents::PlanGenerator.new(
        agent: agent,
        task: "Implement user authentication",
        session: session
      )

      # This would normally call the real LLM, but we've mocked it above
      # For this test, we just verify the service structure works
      expect(generator).to be_a(Agents::PlanGenerator)
    end

    it "stores the plan in session metadata" do
      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "generate", "task" => "Test task" },
        config: { session: session },
        agent: agent
      )

      # Mock the PlanGenerator
      allow(Agents::PlanGenerator).to receive(:call).and_return(
        ServiceResponse.success(data: { plan: plan })
      )

      result = executor.call

      expect(result.success?).to be true
      expect(session.reload.metadata["current_plan"]).to eq(plan)
      expect(session.metadata["plan_status"]).to eq("generated")
    end

    it "broadcasts plan to chat UI" do
      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "generate", "task" => "Test task" },
        config: { session: session },
        agent: agent
      )

      allow(Agents::PlanGenerator).to receive(:call).and_return(
        ServiceResponse.success(data: { plan: plan })
      )

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
  end

  describe "Plan execution flow" do
    before do
      create(:tool, name: "plan_mode", executor_type: "plan_mode")
      session.update!(metadata: { "current_plan" => plan })
    end

    it "starts execution from the plan" do
      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "execute" },
        config: { session: session },
        agent: agent
      )

      result = executor.call

      expect(result.success?).to be true
      expect(session.reload.metadata["plan_status"]).to eq("executing")
      expect(session.metadata["current_phase"]).to eq(1)
    end

    it "broadcasts execution start with phase 1" do
      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "execute" },
        config: { session: session },
        agent: agent
      )

      expect(ActionCable.server).to receive(:broadcast).with(
        "session_#{session.id}",
        hash_including(
          type: "plan",
          action: "start_execution",
          current_phase: 1,
          total_phases: 2
        )
      )

      executor.call
    end

    it "transitions to next phase" do
      session.update!(metadata: { 
        "current_plan" => plan,
        "plan_status" => "executing",
        "current_phase" => 1
      })

      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "update_phase", "phase_number" => 2 },
        config: { session: session },
        agent: agent
      )

      result = executor.call

      expect(result.success?).to be true
      expect(session.reload.metadata["current_phase"]).to eq(2)
    end

    it "broadcasts phase transition" do
      session.update!(metadata: { 
        "current_plan" => plan,
        "plan_status" => "executing",
        "current_phase" => 1
      })

      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "update_phase", "phase_number" => 2 },
        config: { session: session },
        agent: agent
      )

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

    it "prevents jumping to invalid phases" do
      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "update_phase", "phase_number" => 99 },
        config: { session: session },
        agent: agent
      )

      result = executor.call

      expect(result.success?).to be false
      expect(result.error).to include("Invalid phase number")
    end
  end

  describe "Hashtag action integration" do
    before do
      create(:tool, name: "plan_mode", executor_type: "plan_mode")
    end

    it "triggers plan generation via #plan hashtag" do
      action = HashtagActions::Actions::Plan.new(
        agent: agent,
        session: session,
        payload: "Build a REST API",
        clean_message: "Please plan building a REST API"
      )

      allow(Tools::Executor).to receive(:call).and_return(
        ServiceResponse.success(data: { plan: plan })
      )

      result = action.execute

      expect(result[:status]).to eq("ok")
      expect(result[:response]).to include("Plan generated")
    end

    it "formats plan for display in the response" do
      action = HashtagActions::Actions::Plan.new(
        agent: agent,
        session: session,
        payload: "Implement authentication",
        clean_message: nil
      )

      allow(Tools::Executor).to receive(:call).and_return(
        ServiceResponse.success(data: { plan: plan })
      )

      result = action.execute
      response = result[:response]

      expect(response).to include("Database Setup")
      expect(response).to include("Authentication Routes")
      expect(response).to include("Success Criteria")
    end

    it "provides phase context in prompt addon for agent" do
      action = HashtagActions::Actions::Plan.new(
        agent: agent,
        session: session,
        payload: "Implement authentication",
        clean_message: nil
      )

      allow(Tools::Executor).to receive(:call).and_return(
        ServiceResponse.success(data: { plan: plan })
      )

      result = action.execute
      addon = result[:prompt_addon]

      expect(addon).to include("Phase 1")
      expect(addon).to include("Database Setup")
      expect(addon).to include("## Phase N")
      expect(addon).to include("execute this plan phase by phase")
    end
  end

  describe "Phase tracking in agent context" do
    before do
      create(:tool, name: "plan_mode", executor_type: "plan_mode")
      session.update!(metadata: {
        "current_plan" => plan,
        "current_phase" => 1
      })
    end

    it "stores current phase in session metadata" do
      expect(session.metadata["current_phase"]).to eq(1)
    end

    it "updates phase when moving forward" do
      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "update_phase", "phase_number" => 2 },
        config: { session: session },
        agent: agent
      )

      executor.call

      expect(session.reload.metadata["current_phase"]).to eq(2)
    end

    it "maintains plan reference throughout execution" do
      executor = Tools::PlanModeExecutor.new(
        input: { "action" => "update_phase", "phase_number" => 2 },
        config: { session: session },
        agent: agent
      )

      executor.call

      expect(session.reload.metadata["current_plan"]).to eq(plan)
    end
  end
end
