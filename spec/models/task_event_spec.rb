# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskEvent, type: :model do
  describe "associations" do
    it { should belong_to(:task) }
    it { should belong_to(:agent).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:event_type) }
    it { should validate_presence_of(:summary) }
    it { should validate_inclusion_of(:event_type).in_array(TaskEvent::EVENT_TYPES) }

    it "accepts the new event types" do
      task = create(:task)
      %w[updated hook_added hook_removed].each do |event_type|
        event = build(:task_event, task: task, event_type: event_type, summary: "test")
        expect(event).to be_valid, "Expected '#{event_type}' to be valid"
      end
    end
  end

  describe "scopes" do
    let(:task) { create(:task) }

    it ".chronological orders by created_at ascending" do
      old = create(:task_event, task: task, created_at: 2.hours.ago)
      new_event = create(:task_event, task: task, created_at: 1.hour.ago)

      expect(TaskEvent.chronological).to eq([ old, new_event ])
    end

    it ".recent_first orders by created_at descending" do
      old = create(:task_event, task: task, created_at: 2.hours.ago)
      new_event = create(:task_event, task: task, created_at: 1.hour.ago)

      expect(TaskEvent.recent_first).to eq([ new_event, old ])
    end

    it ".by_type filters by event_type" do
      create(:task_event, task: task, event_type: "created", summary: "Created")
      create(:task_event, task: task, event_type: "assigned", summary: "Assigned")

      results = TaskEvent.by_type("created")
      expect(results.count).to eq(1)
      expect(results.first.event_type).to eq("created")
    end

    it ".since filters events after a given time" do
      old = create(:task_event, task: task, created_at: 3.days.ago)
      recent = create(:task_event, task: task, created_at: 1.hour.ago)

      results = TaskEvent.since(1.day.ago)
      expect(results).to include(recent)
      expect(results).not_to include(old)
    end

    it ".before filters events before a given time" do
      old = create(:task_event, task: task, created_at: 3.days.ago)
      recent = create(:task_event, task: task, created_at: 1.hour.ago)

      results = TaskEvent.before(1.day.ago)
      expect(results).to include(old)
      expect(results).not_to include(recent)
    end
  end

  describe "#to_activity_line" do
    let(:task) { create(:task) }
    let(:agent) { create(:agent, name: "Mando") }

    it "formats with agent name when agent is present" do
      event = create(:task_event, task: task, agent: agent, summary: "Task created", created_at: Time.zone.parse("2026-04-20 14:30"))

      expect(event.to_activity_line).to eq("[2026-04-20 14:30] Mando: Task created")
    end

    it "uses 'System' when no agent" do
      event = create(:task_event, task: task, agent: nil, summary: "Auto-assigned", created_at: Time.zone.parse("2026-04-20 14:30"))

      expect(event.to_activity_line).to eq("[2026-04-20 14:30] System: Auto-assigned")
    end
  end
end
