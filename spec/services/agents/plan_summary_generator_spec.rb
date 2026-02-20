# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::PlanSummaryGenerator do
  let(:agent) { create(:agent) }
  let(:session) do
    create(:session, agent: agent, metadata: {
      current_plan: plan,
      plan_generated_at: 2.hours.ago.iso8601,
      plan_started_at: 1.hour.ago.iso8601,
      current_phase: 3
    })
  end

  let(:plan) do
    {
      "overview" => "Build a REST API",
      "context" => "Creating backend for mobile app",
      "phases" => [
        {
          "number" => 1,
          "name" => "Setup",
          "objectives" => ["Initialize project"],
          "approach" => "Create project structure",
          "tools_needed" => ["shell"],
          "expected_output" => "Project ready"
        },
        {
          "number" => 2,
          "name" => "API Endpoints",
          "objectives" => ["Create endpoints"],
          "approach" => "Implement controllers",
          "tools_needed" => ["file_write"],
          "expected_output" => "Endpoints working"
        },
        {
          "number" => 3,
          "name" => "Authentication",
          "objectives" => ["Add JWT"],
          "approach" => "Implement JWT auth",
          "tools_needed" => ["file_write"],
          "expected_output" => "Auth working"
        }
      ],
      "success_criteria" => ["API works", "Auth works"],
      "estimated_duration" => "4 hours"
    }
  end

  before do
    # Add some transcript entries
    session.transcript = [
      { "role" => "user", "content" => "#plan Build a REST API" },
      { "role" => "assistant", "content" => "Creating plan..." },
      { "role" => "assistant", "content" => "## Phase 1: Setup\nSetting up project structure...\n✅ Complete" },
      { "role" => "assistant", "content" => "## Phase 2: API Endpoints\nImplementing endpoints...\n✅ Complete" },
      { "role" => "assistant", "content" => "## Phase 3: Authentication\nAdding JWT authentication...\n✅ Complete" }
    ]
    session.save!
  end

  describe "#call" do
    context "when plan exists" do
      it "returns success with summary data" do
        result = described_class.call(session: session, agent: agent)
        expect(result.success?).to be true
      end

      it "includes summary in response data" do
        result = described_class.call(session: session, agent: agent)
        summary = result.data[:summary]

        expect(summary).to have_key("original_task")
        expect(summary).to have_key("plan_generated_at")
        expect(summary).to have_key("phases_completed")
        expect(summary).to have_key("total_phases")
        expect(summary).to have_key("phase_outcomes")
        expect(summary).to have_key("key_results")
        expect(summary).to have_key("duration")
      end

      it "extracts task from transcript" do
        result = described_class.call(session: session, agent: agent)
        summary = result.data[:summary]

        expect(summary["original_task"]).to eq("Build a REST API")
      end

      it "counts completed phases" do
        result = described_class.call(session: session, agent: agent)
        summary = result.data[:summary]

        expect(summary["phases_completed"]).to eq(3)
        expect(summary["total_phases"]).to eq(3)
      end

      it "calculates execution duration" do
        result = described_class.call(session: session, agent: agent)
        summary = result.data[:summary]

        # Should be approximately 1 hour (between started and now)
        expect(summary["duration"]).to include("hour")
      end

      it "generates markdown document" do
        result = described_class.call(session: session, agent: agent)
        markdown = result.data[:markdown]

        expect(markdown).to include("# Plan Summary")
        expect(markdown).to include("Build a REST API")
        expect(markdown).to include("3/3 phases completed")
        expect(markdown).to include("## Original Plan")
        expect(markdown).to include("## Execution Summary")
        expect(markdown).to include("Phase 1")
        expect(markdown).to include("Phase 2")
        expect(markdown).to include("Phase 3")
      end

      it "includes success criteria in markdown" do
        result = described_class.call(session: session, agent: agent)
        markdown = result.data[:markdown]

        expect(markdown).to include("Success Criteria")
        expect(markdown).to include("API works")
        expect(markdown).to include("Auth works")
      end

      it "extracts learnings from transcript" do
        result = described_class.call(session: session, agent: agent)
        learnings = result.data[:learnings]

        expect(learnings).to be_an(Array)
        expect(learnings).to include("Successfully completed all planned phases")
      end

      it "identifies key results from transcript" do
        result = described_class.call(session: session, agent: agent)
        summary = result.data[:summary]

        # Should find completion markers
        expect(summary["key_results"]).to be_an(Array)
      end

      it "includes phase outcomes with status" do
        result = described_class.call(session: session, agent: agent)
        summary = result.data[:summary]
        outcomes = summary["phase_outcomes"]

        expect(outcomes["1"]).to have_key("phase_number")
        expect(outcomes["1"]).to have_key("phase_name")
        expect(outcomes["1"]).to have_key("status")
        expect(outcomes["1"]["status"]).to eq("completed")
      end

      it "includes generation timestamp" do
        result = described_class.call(session: session, agent: agent)
        expect(result.data[:generated_at]).to be_present
      end
    end

    context "when no plan exists" do
      before { session.update!(metadata: {}) }

      it "returns failure" do
        result = described_class.call(session: session, agent: agent)
        expect(result.success?).to be false
        expect(result.error).to eq("No plan available to summarize")
      end
    end

    context "when transcript has partial completion" do
      before do
        session.transcript = [
          { "role" => "assistant", "content" => "## Phase 1: Setup\n✅ Complete" },
          { "role" => "assistant", "content" => "## Phase 2: API Endpoints\nIn progress..." }
        ]
        session.metadata["current_phase"] = 2
        session.save!
      end

      it "shows partial completion status" do
        result = described_class.call(session: session, agent: agent)
        summary = result.data[:summary]

        expect(summary["phases_completed"]).to eq(2)
        expect(summary["total_phases"]).to eq(3)
      end

      it "includes partial completion in learnings" do
        result = described_class.call(session: session, agent: agent)
        learnings = result.data[:learnings]

        expect(learnings).to include("Partially completed plan - 2 of 3 phases finished")
      end
    end

    context "with invalid task extraction" do
      before do
        session.transcript = []
        session.save!
      end

      it "uses default task name" do
        result = described_class.call(session: session, agent: agent)
        summary = result.data[:summary]

        expect(summary["original_task"]).to eq("Plan creation task")
      end
    end

    context "markdown formatting" do
      it "includes agent name in markdown" do
        result = described_class.call(session: session, agent: agent)
        markdown = result.data[:markdown]

        expect(markdown).to include(agent.name)
      end

      it "includes session ID in markdown" do
        result = described_class.call(session: session, agent: agent)
        markdown = result.data[:markdown]

        expect(markdown).to include(session.id.to_s)
      end

      it "formats phases with proper markdown structure" do
        result = described_class.call(session: session, agent: agent)
        markdown = result.data[:markdown]

        expect(markdown).to match(/\*\*Phase \d+:/)
        expect(markdown).to match(/\*Objectives:\*/)
        expect(markdown).to match(/\*Approach:\*/)
      end

      it "includes completion status emoji" do
        result = described_class.call(session: session, agent: agent)
        markdown = result.data[:markdown]

        expect(markdown).to include("✅ COMPLETED")
      end
    end
  end
end
