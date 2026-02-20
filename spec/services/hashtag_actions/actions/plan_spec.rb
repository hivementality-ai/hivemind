# frozen_string_literal: true

require "rails_helper"

RSpec.describe HashtagActions::Actions::Plan do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
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
          "objectives" => ["Research requirements", "Check existing code"],
          "approach" => "Review docs and codebase",
          "tools_needed" => ["file_read", "web_search"],
          "expected_output" => "Understanding of requirements"
        }
      ],
      "success_criteria" => ["Feature works", "Tests pass"],
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
    # Mock the plan_mode tool
    create(:tool, name: "plan_mode", executor_type: "plan_mode")
  end

  describe "#execute" do
    context "when plan generation succeeds" do
      before do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.success(data: { plan: plan })
        )
      end

      it "calls the plan_mode tool with generate action" do
        expect(Tools::Executor).to receive(:call).with(
          tool: instance_of(Tool),
          input: hash_including("action" => "generate", "task" => payload),
          agent: agent,
          session: session
        ).and_return(ServiceResponse.success(data: { plan: plan }))

        action.execute
      end

      it "returns success response" do
        result = action.execute
        expect(result[:status]).to eq("ok")
      end

      it "includes plan summary in response" do
        result = action.execute
        expect(result[:response]).to include("✅ Plan generated!")
        expect(result[:response]).to include("Research")
      end

      it "includes phase context in prompt addon" do
        result = action.execute
        expect(result[:prompt_addon]).to include("Phase 1")
        expect(result[:prompt_addon]).to include("Research")
      end

      it "does not bypass LLM" do
        result = action.execute
        expect(result[:bypass]).to be false
      end

      context "when payload is empty, uses clean_message" do
        let(:payload) { "" }

        it "uses clean_message as task" do
          expect(Tools::Executor).to receive(:call).with(
            tool: instance_of(Tool),
            input: hash_including("task" => clean_message),
            agent: agent,
            session: session
          ).and_return(ServiceResponse.success(data: { plan: plan }))

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
          ).and_return(ServiceResponse.success(data: { plan: plan }))

          action.execute
        end
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
      before do
        Tool.where(name: "plan_mode").delete_all
      end

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

      it "returns error response with error message" do
        result = action.execute
        expect(result[:status]).to eq("error")
        expect(result[:response]).to include("Planning error")
      end
    end
  end

  describe "plan formatting" do
    before do
      allow(Tools::Executor).to receive(:call).and_return(
        ServiceResponse.success(data: { plan: plan })
      )
    end

    it "includes all plan sections in the response" do
      result = action.execute
      response = result[:response]

      expect(response).to include("Overview")
      expect(response).to include("Context")
      expect(response).to include("Phases")
      expect(response).to include("Success Criteria")
      expect(response).to include("Estimated Duration")
    end

    it "formats phases with numbers and names" do
      result = action.execute
      response = result[:response]

      expect(response).to include("Phase 1:")
      expect(response).to include("Research")
    end

    it "includes phase objectives and approach" do
      result = action.execute
      response = result[:response]

      expect(response).to include("Objectives")
      expect(response).to include("Research requirements")
      expect(response).to include("Approach")
      expect(response).to include("Review docs and codebase")
    end

    it "lists tools needed for each phase" do
      result = action.execute
      response = result[:response]

      expect(response).to include("Tools needed")
      expect(response).to include("file_read")
    end
  end

  describe "phase context building" do
    before do
      allow(Tools::Executor).to receive(:call).and_return(
        ServiceResponse.success(data: { plan: plan })
      )
    end

    it "includes phase descriptions in prompt addon" do
      result = action.execute
      addon = result[:prompt_addon]

      expect(addon).to include("Phase 1")
      expect(addon).to include("Research")
    end

    it "includes execution instructions in prompt addon" do
      result = action.execute
      addon = result[:prompt_addon]

      expect(addon).to include("## Phase N")
      expect(addon).to include("execute this plan phase by phase")
    end
  end
end
