# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::DeepResearchStatusExecutor do
  subject { described_class.new(input: input, config: config, agent: agent) }

  let(:agent) { create(:agent) }
  let(:config) { {} }
  let(:input) { { "action" => action } }
  let(:action) { "status" }

  describe "#call" do
    context "status action" do
      let(:input) { { "action" => "status", "task_key" => task_key } }
      let(:task_key) { "abc123" }

      context "with valid task_key" do
        let!(:rs) { create(:research_session, :running, task_key: task_key, agent: agent) }

        it "returns session status" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Research Session: #{task_key}")
          expect(result.data[:output]).to include("Status: 🔄 Running")
          expect(result.data[:output]).to include("Depth: standard")
        end

        it "shows progress log" do
          allow(ActionCable.server).to receive(:broadcast)
          rs.log_progress("Searching for sources...")

          result = subject.call
          expect(result.data[:output]).to include("Searching for sources...")
        end

        it "shows sources count" do
          rs.update!(sources_count: 5)

          result = subject.call
          expect(result.data[:output]).to include("Sources: 5")
        end
      end

      context "with completed session" do
        let!(:rs) { create(:research_session, :completed, task_key: task_key, agent: agent) }

        it "shows report for completed session" do
          result = subject.call
          expect(result.data[:output]).to include("Status: ✅ Completed")
          expect(result.data[:output]).to include("=== Report ===")
          expect(result.data[:output]).to include("Research Report")
        end
      end

      context "with failed session" do
        let!(:rs) { create(:research_session, :failed, task_key: task_key, agent: agent) }

        it "shows error for failed session" do
          result = subject.call
          expect(result.data[:output]).to include("Status: ❌ Failed")
          expect(result.data[:output]).to include("=== Error ===")
          expect(result.data[:output]).to include("LLM provider resolution failed")
        end
      end

      context "with nonexistent task_key" do
        let(:task_key) { "nonexistent" }

        it "returns error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("Research session not found: nonexistent")
        end
      end

      context "without task_key" do
        let(:input) { { "action" => "status" } }

        it "returns error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("No task_key provided")
        end
      end

      context "with session belonging to different agent" do
        let!(:rs) { create(:research_session, task_key: task_key, agent: create(:agent)) }

        it "returns not found error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("Session abc123 not found or not accessible")
        end
      end
    end

    context "list action" do
      let(:action) { "list" }

      context "with sessions for current agent" do
        let!(:rs1) { create(:research_session, :completed, agent: agent) }
        let!(:rs2) { create(:research_session, :running, agent: agent) }
        let!(:rs3) { create(:research_session, agent: create(:agent)) }

        it "lists sessions for current agent only" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to include(rs1.task_key)
          expect(result.data[:output]).to include(rs2.task_key)
          expect(result.data[:output]).not_to include(rs3.task_key)
        end

        it "shows status icons" do
          result = subject.call
          expect(result.data[:output]).to include("✅")
          expect(result.data[:output]).to include("🔄")
        end
      end

      context "with no sessions" do
        it "shows no sessions message" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("No research sessions found.")
        end
      end

      context "with no agent context" do
        let(:agent) { nil }
        let!(:rs1) { create(:research_session, :completed) }
        let!(:rs2) { create(:research_session, :running) }

        it "shows all recent sessions" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to include(rs1.task_key)
          expect(result.data[:output]).to include(rs2.task_key)
        end
      end
    end

    context "cancel action" do
      let(:input) { { "action" => "cancel", "task_key" => task_key } }
      let(:task_key) { "abc123" }

      context "with active session" do
        let!(:rs) { create(:research_session, :running, task_key: task_key, agent: agent) }

        it "cancels the session" do
          result = subject.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Cancelled research session abc123")

          rs.reload
          expect(rs.status).to eq("cancelled")
          expect(rs.completed_at).to be_present
        end
      end

      context "with inactive session" do
        let!(:rs) { create(:research_session, :completed, task_key: task_key, agent: agent) }

        it "returns error for inactive session" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not active")
        end
      end

      context "with nonexistent task_key" do
        let(:task_key) { "nonexistent" }

        it "returns error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("Research session not found: nonexistent")
        end
      end

      context "without task_key" do
        let(:input) { { "action" => "cancel" } }

        it "returns error" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to eq("No task_key provided")
        end
      end
    end

    context "invalid action" do
      let(:action) { "invalid" }

      it "returns error for unknown action" do
        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("Unknown action: invalid. Supported: status, list, cancel")
      end
    end

    context "when action is not specified" do
      let(:input) { { "task_key" => "abc123" } }
      let!(:rs) { create(:research_session, task_key: "abc123", agent: agent) }

      it "defaults to status action" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Research Session: abc123")
      end
    end
  end
end
