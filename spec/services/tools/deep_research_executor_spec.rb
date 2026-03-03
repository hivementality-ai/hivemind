# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::DeepResearchExecutor do
  subject { described_class.new(input: input, config: config, agent: agent) }

  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:config) { { session: session } }
  let(:input) { { "query" => query } }
  let(:query) { "What are the latest advances in quantum computing?" }

  before do
    allow(SecureRandom).to receive(:hex).and_return("abc123")
    allow(DeepResearchJob).to receive(:perform_later)
  end

  describe "#call" do
    context "with valid query" do
      it "creates research session with defaults" do
        expect {
          subject.call
        }.to change { ResearchSession.count }.by(1)

        rs = ResearchSession.last
        expect(rs.agent).to eq(agent)
        expect(rs.session).to eq(session)
        expect(rs.query).to eq(query)
        expect(rs.depth).to eq("standard")
        expect(rs.focus).to eq("general")
        expect(rs.output_format).to eq("report")
        expect(rs.task_key).to eq("abc123")
        expect(rs.status).to eq("queued")
      end

      it "starts background job" do
        subject.call
        expect(DeepResearchJob).to have_received(:perform_later).with(ResearchSession.last.id)
      end

      it "returns task_key immediately" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:task_key]).to eq("abc123")
        expect(result.data[:exit_code]).to eq(0)
        expect(result.data[:output]).to include("Started deep research")
        expect(result.data[:output]).to include("Task ID: abc123")
      end

      it "uses specified depth" do
        input["depth"] = "deep"

        subject.call
        rs = ResearchSession.last
        expect(rs.depth).to eq("deep")
      end

      it "uses specified focus" do
        input["focus"] = "scientific"

        subject.call
        rs = ResearchSession.last
        expect(rs.focus).to eq("scientific")
      end

      it "uses specified output_format" do
        input["output_format"] = "bullet_points"

        subject.call
        rs = ResearchSession.last
        expect(rs.output_format).to eq("bullet_points")
      end
    end

    context "with invalid input" do
      it "rejects empty query" do
        input["query"] = ""

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to eq("No query provided")
        expect(ResearchSession.count).to eq(0)
      end

      it "rejects invalid depth" do
        input["depth"] = "extreme"

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to include("Invalid depth")
      end

      it "rejects invalid focus" do
        input["focus"] = "mystical"

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to include("Invalid focus")
      end

      it "rejects invalid output_format" do
        input["output_format"] = "poem"

        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to include("Invalid output_format")
      end
    end

    context "with no session context" do
      let(:config) { {} }

      it "finds session from agent" do
        create(:session, agent: agent, updated_at: 1.hour.ago)
        recent_session = create(:session, agent: agent, updated_at: 1.minute.ago)

        subject.call
        rs = ResearchSession.last
        expect(rs.session).to eq(recent_session)
      end

      it "returns error when no session available" do
        subject_no_agent = described_class.new(input: input, config: {}, agent: nil)

        result = subject_no_agent.call
        expect(result).not_to be_success
        expect(result.error).to eq("No session context available")
      end
    end

    context "when record creation fails" do
      before do
        allow(ResearchSession).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(ResearchSession.new))
      end

      it "returns failure" do
        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to include("Failed to start deep research")
      end
    end
  end
end
