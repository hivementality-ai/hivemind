# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::EventLogger do
  let(:task) { create(:task) }
  let(:agent) { create(:agent) }

  describe ".call" do
    it "creates a TaskEvent" do
      expect {
        described_class.call(task: task, event_type: "status_change", summary: "Status changed to done")
      }.to change(TaskEvent, :count).by(1)
    end

    it "sets all attributes correctly" do
      event = described_class.call(
        task: task,
        agent: agent,
        event_type: "assigned",
        summary: "Assigned to Grogu",
        metadata: { agent_name: "Grogu" }
      )

      expect(event.task).to eq(task)
      expect(event.agent).to eq(agent)
      expect(event.event_type).to eq("assigned")
      expect(event.summary).to eq("Assigned to Grogu")
      expect(event.metadata["agent_name"]).to eq("Grogu")
      expect(event.created_at).to be_present
    end
  end
end
