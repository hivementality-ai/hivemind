# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResearchSession, type: :model do
  subject { build(:research_session) }

  describe "associations" do
    it { is_expected.to belong_to(:agent) }
    it { is_expected.to belong_to(:session) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:query) }
    it { is_expected.to validate_presence_of(:task_key) }
    it { is_expected.to validate_uniqueness_of(:task_key) }
    it { is_expected.to validate_inclusion_of(:status).in_array(ResearchSession::STATUSES) }
    it { is_expected.to validate_inclusion_of(:depth).in_array(ResearchSession::DEPTHS) }
    it { is_expected.to validate_inclusion_of(:focus).in_array(ResearchSession::FOCUSES) }
    it { is_expected.to validate_inclusion_of(:output_format).in_array(ResearchSession::OUTPUT_FORMATS) }
  end

  describe "scopes" do
    describe ".active" do
      it "returns queued and running sessions" do
        queued = create(:research_session, status: "queued")
        running = create(:research_session, :running)
        create(:research_session, :completed)
        create(:research_session, :failed)

        expect(described_class.active).to contain_exactly(queued, running)
      end
    end

    describe ".recent" do
      it "returns sessions ordered by created_at desc with default limit" do
        sessions = create_list(:research_session, 7)
        expect(described_class.recent.count).to eq(5)
        expect(described_class.recent.first).to eq(sessions.last)
      end

      it "accepts a custom limit" do
        create_list(:research_session, 3)
        expect(described_class.recent(2).count).to eq(2)
      end
    end

    describe ".for_agent" do
      it "returns sessions for specified agent" do
        agent = create(:agent)
        mine = create(:research_session, agent: agent)
        create(:research_session) # different agent

        expect(described_class.for_agent(agent)).to contain_exactly(mine)
      end
    end
  end

  describe "#log_progress" do
    let(:research_session) { create(:research_session, :running) }

    it "appends to progress_log and saves" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "session_#{research_session.session.id}",
        hash_including(type: "research_progress", task_key: research_session.task_key)
      )

      research_session.log_progress("Searching...")

      research_session.reload
      expect(research_session.progress_log.size).to eq(1)
      expect(research_session.progress_log.first["message"]).to eq("Searching...")
    end

    it "accumulates multiple progress entries" do
      allow(ActionCable.server).to receive(:broadcast)

      research_session.log_progress("Step 1")
      research_session.log_progress("Step 2")

      research_session.reload
      expect(research_session.progress_log.size).to eq(2)
    end
  end

  describe "#add_source" do
    let(:research_session) { create(:research_session, :running) }

    it "appends source and increments count" do
      source = { title: "Test", url: "https://example.com", snippet: "A test" }

      research_session.add_source(source)

      research_session.reload
      expect(research_session.sources.size).to eq(1)
      expect(research_session.sources_count).to eq(1)
    end
  end

  describe "#add_finding" do
    let(:research_session) { create(:research_session, :running) }

    it "appends finding" do
      finding = { topic: "AI", summary: "AI is advancing" }

      research_session.add_finding(finding)

      research_session.reload
      expect(research_session.findings.size).to eq(1)
      expect(research_session.findings.first["topic"]).to eq("AI")
    end
  end

  describe "#complete!" do
    let(:research_session) { create(:research_session, :running) }

    it "sets status, report, and completed_at" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "session_#{research_session.session.id}",
        hash_including(type: "research_complete", task_key: research_session.task_key)
      )

      research_session.complete!("Final report text")

      research_session.reload
      expect(research_session.status).to eq("completed")
      expect(research_session.report).to eq("Final report text")
      expect(research_session.completed_at).to be_present
    end
  end

  describe "#fail!" do
    let(:research_session) { create(:research_session, :running) }

    it "sets status, error_message, and completed_at" do
      research_session.fail!("Something went wrong")

      research_session.reload
      expect(research_session.status).to eq("failed")
      expect(research_session.error_message).to eq("Something went wrong")
      expect(research_session.completed_at).to be_present
    end
  end

  describe "#cancelled?" do
    it "returns true when status is cancelled" do
      rs = create(:research_session, :cancelled)
      expect(rs.cancelled?).to be true
    end

    it "returns false when status is running" do
      rs = create(:research_session, :running)
      expect(rs.cancelled?).to be false
    end
  end

  describe "#duration_seconds" do
    it "returns nil when not started" do
      rs = build(:research_session)
      expect(rs.duration_seconds).to be_nil
    end

    it "returns duration when completed" do
      rs = build(:research_session, :completed)
      expect(rs.duration_seconds).to be > 0
    end

    it "returns ongoing duration when running" do
      rs = build(:research_session, :running)
      expect(rs.duration_seconds).to be > 0
    end
  end

  describe "#active?" do
    it "returns true for queued" do
      expect(build(:research_session, status: "queued").active?).to be true
    end

    it "returns true for running" do
      expect(build(:research_session, :running).active?).to be true
    end

    it "returns false for completed" do
      expect(build(:research_session, :completed).active?).to be false
    end
  end
end
