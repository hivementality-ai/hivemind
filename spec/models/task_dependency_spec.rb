# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskDependency, type: :model do
  describe "associations" do
    it { should belong_to(:task) }
    it { should belong_to(:depends_on).class_name("Task") }
  end

  describe "validations" do
    it "prevents duplicate dependencies" do
      task_a = create(:task)
      task_b = create(:task)
      create(:task_dependency, task: task_a, depends_on: task_b)

      dup = build(:task_dependency, task: task_a, depends_on: task_b)
      expect(dup).not_to be_valid
      expect(dup.errors[:depends_on_id]).to include("dependency already exists")
    end

    it "prevents self-dependency" do
      task = create(:task)
      dep = build(:task_dependency, task: task, depends_on: task)
      expect(dep).not_to be_valid
      expect(dep.errors[:depends_on_id]).to include("a task cannot depend on itself")
    end

    it "prevents circular dependencies" do
      task_a = create(:task)
      task_b = create(:task)
      create(:task_dependency, task: task_a, depends_on: task_b)

      circular = build(:task_dependency, task: task_b, depends_on: task_a)
      expect(circular).not_to be_valid
      expect(circular.errors[:base].first).to include("circular dependency")
    end

    it "allows valid dependencies" do
      task_a = create(:task)
      task_b = create(:task)
      dep = build(:task_dependency, task: task_a, depends_on: task_b)
      expect(dep).to be_valid
    end
  end
end
