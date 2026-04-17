# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodingAgentTask, type: :model do
  describe "validations" do
    it { should validate_presence_of(:task) }
    it { should validate_presence_of(:task_key) }
    it { should validate_presence_of(:cli) }
    it { should validate_inclusion_of(:cli).in_array(%w[claude codex aider]) }
    it { should validate_inclusion_of(:status).in_array(%w[pending running completed failed]) }
  end

  describe "associations" do
    it { should belong_to(:agent) }
    it { should belong_to(:session) }
  end

  describe "#duration_seconds" do
    let(:agent)   { create(:agent) }
    let(:session) { create(:session, agent: agent) }
    let(:task) do
      create(:coding_agent_task,
             agent: agent,
             session: session,
             started_at: 10.seconds.ago,
             completed_at: Time.current)
    end

    it "returns elapsed seconds between started_at and completed_at" do
      expect(task.duration_seconds).to be_within(1).of(10)
    end

    it "returns nil when not yet started" do
      task.update_columns(started_at: nil)
      expect(task.duration_seconds).to be_nil
    end
  end

  describe "status predicates" do
    let(:agent)   { create(:agent) }
    let(:session) { create(:session, agent: agent) }

    it "#running? returns true when status is running" do
      t = create(:coding_agent_task, agent: agent, session: session, status: "running")
      expect(t.running?).to be true
      expect(t.completed?).to be false
    end

    it "#completed? returns true when status is completed" do
      t = create(:coding_agent_task, agent: agent, session: session, status: "completed")
      expect(t.completed?).to be true
      expect(t.failed?).to be false
    end

    it "#failed? returns true when status is failed" do
      t = create(:coding_agent_task, agent: agent, session: session, status: "failed")
      expect(t.failed?).to be true
    end
  end
end
