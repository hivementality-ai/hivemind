# frozen_string_literal: true

require "rails_helper"

RSpec.describe HashtagActions::Actions::ExitPlan do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }

  let(:plan) do
    {
      "overview" => "Test plan",
      "context" => "Testing",
      "phases" => [
        { "number" => 1, "name" => "Phase 1", "objectives" => ["Test"] }
      ],
      "success_criteria" => ["Works"],
      "estimated_duration" => "1 hour"
    }
  end

  let(:summary) do
    {
      "original_task" => "Test task",
      "phases_completed" => 1,
      "total_phases" => 1,
      "duration" => "30 minutes",
      "key_results" => ["Completed phase 1"]
    }
  end

  subject(:action) { described_class.new(agent: agent, session: session) }

  before do
    create(:tool, name: "plan_mode", executor_type: "plan_mode")
    session.update!(metadata: { current_plan: plan })
  end

  def stub_exit_success(sum = summary, md = "# Plan Summary")
    allow(Tools::Executor).to receive(:call).and_return(
      ServiceResponse.success(data: { summary: sum, markdown: md })
    )
  end

  describe "#execute" do
    context "when plan mode exits successfully" do
      before { stub_exit_success }

      it "calls the plan_mode tool with exit action" do
        expect(Tools::Executor).to receive(:call).with(
          tool: instance_of(Tool),
          input: hash_including(action: "exit"),
          agent: agent,
          session: session
        ).and_return(ServiceResponse.success(data: { summary: summary, markdown: "# Plan Summary" }))

        action.execute
      end

      it "returns success status" do
        result = action.execute
        expect(result[:status]).to eq("ok")
      end

      it "includes completion header in response" do
        result = action.execute
        expect(result[:response]).to include("Plan Execution Complete")
      end

      it "includes task name in response" do
        result = action.execute
        expect(result[:response]).to include("Test task")
      end

      it "includes progress in response" do
        result = action.execute
        expect(result[:response]).to include("1/1 phases completed")
      end

      it "includes key results" do
        result = action.execute
        expect(result[:response]).to include("Key Results")
        expect(result[:response]).to include("Completed phase 1")
      end

      it "includes save options" do
        result = action.execute
        response = result[:response]
        expect(response).to include("Download summary as markdown")
        expect(response).to include("Save to workspace")
        expect(response).to include("Copy summary to clipboard")
      end

      it "includes metadata" do
        result = action.execute
        expect(result[:metadata]).to have_key(:summary)
        expect(result[:metadata]).to have_key(:markdown)
        expect(result[:metadata]).to have_key(:session_id)
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

    context "when plan exit fails" do
      before do
        allow(Tools::Executor).to receive(:call).and_return(
          ServiceResponse.failure(error: "No active plan")
        )
      end

      it "returns error response" do
        result = action.execute
        expect(result[:status]).to eq("error")
        expect(result[:response]).to include("Failed to exit plan mode")
      end
    end

    context "when an exception occurs" do
      before do
        allow(Tools::Executor).to receive(:call).and_raise(StandardError, "Unexpected error")
      end

      it "returns error with message" do
        result = action.execute
        expect(result[:status]).to eq("error")
        expect(result[:response]).to include("Exit plan error")
      end
    end
  end

  describe "response formatting with multi-phase summary" do
    let(:full_summary) do
      {
        "original_task" => "Build authentication system",
        "phases_completed" => 3,
        "total_phases" => 3,
        "duration" => "4 hours",
        "key_results" => [
          "User table created",
          "Login endpoint working",
          "JWT authentication implemented"
        ]
      }
    end

    before { stub_exit_success(full_summary) }

    it "formats task name" do
      result = action.execute
      expect(result[:response]).to include("Build authentication system")
    end

    it "formats progress" do
      result = action.execute
      expect(result[:response]).to include("3/3 phases completed")
    end

    it "includes all key results" do
      result = action.execute
      full_summary["key_results"].each do |res|
        expect(result[:response]).to include(res)
      end
    end

    it "uses proper emoji indicators" do
      result = action.execute
      response = result[:response]
      expect(response).to include("✅")
      expect(response).to include("📥")
      expect(response).to include("💾")
      expect(response).to include("📋")
    end
  end
end
