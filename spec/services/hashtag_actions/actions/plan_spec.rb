# frozen_string_literal: true

require "rails_helper"

RSpec.describe HashtagActions::Actions::Plan do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent, metadata: {}) }
  let(:payload) { "Build a feature" }
  let(:clean_message) { "Please plan for building a feature" }

  let(:plan) do
    {
      "overview" => "Build a feature",
      "context" => "Adding new functionality to the application",
      "phases" => [
        {
          "number" => 1,
          "name" => "Research",
          "objectives" => [ "Research requirements", "Check existing code" ],
          "approach" => "Review docs and codebase",
          "tools_needed" => [ "file_read", "web_search" ],
          "expected_output" => "Understanding of requirements"
        }
      ],
      "success_criteria" => [ "Feature works", "Tests pass" ],
      "estimated_duration" => "2 hours"
    }
  end

  subject(:action) do
    described_class.new(
      agent: agent,
      session: session,
      payload: payload,
      clean_message: clean_message
    )
  end

  before do
    create(:tool, name: "plan_mode", executor_type: "plan_mode")
  end

  # Helper: simulate what the executor does (saves plan to session metadata)
  def stub_successful_plan_generation
    allow(Tools::Executor).to receive(:call) do |**args|
      args[:session].update!(metadata: (args[:session].metadata || {}).merge("current_plan" => plan))
      ServiceResponse.success(data: { plan: plan })
    end
  end

  describe "#execute" do
    context "when plan generation succeeds" do
      before { stub_successful_plan_generation }

      it "calls the plan_mode tool with generate action" do
        expect(Tools::Executor).to receive(:call).with(
          tool: instance_of(Tool),
          input: hash_including("action" => "generate", "task" => payload),
          agent: agent,
          session: session
        ) do |**args|
          args[:session].update!(metadata: (args[:session].metadata || {}).merge("current_plan" => plan))
          ServiceResponse.success(data: { plan: plan })
        end

        action.execute
      end

      it "returns success status" do
        result = action.execute
        expect(result[:status]).to eq("ok")
      end

      it "bypasses LLM (plan card saved to transcript by executor)" do
        result = action.execute
        expect(result[:bypass]).to be true
      end

      it "returns nil response (plan displayed via card)" do
        result = action.execute
        expect(result[:response]).to be_nil
      end

      context "when payload is empty, uses clean_message" do
        let(:payload) { "" }

        it "uses clean_message as task" do
          expect(Tools::Executor).to receive(:call).with(
            tool: instance_of(Tool),
            input: hash_including("task" => clean_message),
            agent: agent,
            session: session
          ) do |**args|
            args[:session].update!(metadata: (args[:session].metadata || {}).merge("current_plan" => plan))
            ServiceResponse.success(data: { plan: plan })
          end

          action.execute
        end
      end

      context "when both payload and clean_message are empty" do
        let(:payload) { "" }
        let(:clean_message) { "" }

        it "uses default task" do
          expect(Tools::Executor).to receive(:call).with(
            tool: instance_of(Tool),
            input: hash_including("task" => "General task planning"),
            agent: agent,
            session: session
          ) do |**args|
            args[:session].update!(metadata: (args[:session].metadata || {}).merge("current_plan" => plan))
            ServiceResponse.success(data: { plan: plan })
          end

          action.execute
        end
      end
    end

    context "when executor succeeds but plan not saved to session" do
      before do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.success(data: { plan: plan })
        )
      end

      it "returns error about missing plan" do
        result = action.execute
        expect(result[:status]).to eq("error")
        expect(result[:response]).to include("couldn't retrieve")
      end
    end

    context "when plan generation fails" do
      before do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.failure(error: "LLM generation error")
        )
      end

      it "returns error response" do
        result = action.execute
        expect(result[:status]).to eq("error")
        expect(result[:response]).to include("Failed to generate plan")
      end
    end

    context "when plan_mode tool is not found" do
      before { Tool.where(name: "plan_mode").delete_all }

      it "returns error response" do
        result = action.execute
        expect(result[:status]).to eq("error")
        expect(result[:response]).to include("tool not found")
      end
    end

    context "when an exception occurs" do
      before do
        allow(Tools::Executor).to receive(:call).and_raise(StandardError, "Unexpected error")
      end

      it "returns error with message" do
        result = action.execute
        expect(result[:status]).to eq("error")
        expect(result[:response]).to include("Planning error")
        expect(result[:response]).to include("Unexpected error")
      end
    end
  end

  describe "private #build_phase_context" do
    it "includes phase descriptions" do
      context = action.send(:build_phase_context, plan)
      expect(context).to include("Phase 1")
      expect(context).to include("Research")
    end

    it "includes execution instructions" do
      context = action.send(:build_phase_context, plan)
      expect(context).to include("## Phase N")
      expect(context).to include("execute this plan phase by phase")
    end
  end

  describe "private #format_plan_for_display" do
    it "includes plan overview" do
      output = action.send(:format_plan_for_display, plan)
      expect(output).to include("Build a feature")
    end

    it "formats phases with numbers and names" do
      output = action.send(:format_plan_for_display, plan)
      expect(output).to include("Phase 1")
      expect(output).to include("Research")
    end

    it "includes phase objectives" do
      output = action.send(:format_plan_for_display, plan)
      expect(output).to include("Research requirements")
    end

    it "includes success criteria" do
      output = action.send(:format_plan_for_display, plan)
      expect(output).to include("Success Criteria")
      expect(output).to include("Feature works")
    end

    it "includes estimated duration" do
      output = action.send(:format_plan_for_display, plan)
      expect(output).to include("2 hours")
    end
  end
end
