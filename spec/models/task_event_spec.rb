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
  end
end
