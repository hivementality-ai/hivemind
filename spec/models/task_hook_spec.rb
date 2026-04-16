# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskHook, type: :model do
  describe "associations" do
    it { should belong_to(:task).optional }
    it { should belong_to(:task_template).optional }
    it { should belong_to(:team).optional }
    it { should belong_to(:skill).optional }
  end

  describe "validations" do
    it { should validate_inclusion_of(:trigger).in_array(TaskHook::TRIGGERS) }
    it { should validate_inclusion_of(:on_status).in_array(Task::STATUSES) }

    it "requires exactly one owner" do
      hook = build(:task_hook, task: nil, task_template: nil, team: nil)
      expect(hook).not_to be_valid
      expect(hook.errors[:base]).to include("must belong to a task, task template, or team")
    end

    it "disallows multiple owners" do
      task = create(:task)
      template = create(:task_template)
      hook = build(:task_hook, task: task, task_template: template)
      expect(hook).not_to be_valid
      expect(hook.errors[:base]).to include("can only belong to one of: task, task template, or team")
    end

    it "is valid with just a task" do
      hook = build(:task_hook, task: create(:task), skill: create(:skill))
      expect(hook).to be_valid
    end

    it "is valid with just a template" do
      hook = build(:task_hook, task_template: create(:task_template), skill: create(:skill))
      expect(hook).to be_valid
    end

    it "is valid with just a team" do
      hook = build(:task_hook, :for_team, skill: create(:skill))
      expect(hook).to be_valid
    end

    it "is valid without a skill (uses default behavior)" do
      hook = build(:task_hook, :for_team, :without_skill)
      expect(hook).to be_valid
    end
  end

  describe "scopes" do
    let(:task) { create(:task) }
    let(:skill) { create(:skill) }

    let!(:pre_hook) { create(:task_hook, :pre, :for_task, task: task, skill: skill, on_status: "in_progress") }
    let!(:post_hook) { create(:task_hook, :post, :for_task, task: task, skill: skill, on_status: "done") }
    let!(:disabled_hook) { create(:task_hook, :for_task, task: task, skill: skill, on_status: "done", enabled: false) }

    it ".enabled excludes disabled hooks" do
      expect(TaskHook.enabled).to include(pre_hook, post_hook)
      expect(TaskHook.enabled).not_to include(disabled_hook)
    end

    it ".pre_hooks returns only pre hooks" do
      expect(TaskHook.pre_hooks).to include(pre_hook)
      expect(TaskHook.pre_hooks).not_to include(post_hook)
    end

    it ".post_hooks returns only post hooks" do
      expect(TaskHook.post_hooks).to include(post_hook)
      expect(TaskHook.post_hooks).not_to include(pre_hook)
    end

    it ".for_status filters by on_status" do
      expect(TaskHook.for_status("done")).to include(post_hook, disabled_hook)
      expect(TaskHook.for_status("done")).not_to include(pre_hook)
    end
  end
end
