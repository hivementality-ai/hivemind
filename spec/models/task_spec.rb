# frozen_string_literal: true

require "rails_helper"

RSpec.describe Task, type: :model do
  describe "associations" do
    it { should belong_to(:created_by_agent).class_name("Agent").optional }
    it { should belong_to(:assigned_to_agent).class_name("Agent").optional }
    it { should belong_to(:task_template).optional }
    it { should belong_to(:project).optional }
    it { should belong_to(:project_milestone).optional }
    it { should belong_to(:session).optional }
    it { should have_many(:task_hooks).dependent(:destroy) }
    it { should have_many(:task_events).dependent(:destroy) }
    it { should have_many(:task_dependencies).dependent(:destroy) }
    it { should have_many(:blocking_tasks).through(:task_dependencies) }
  end

  describe "validations" do
    it { should validate_presence_of(:title) }
    it { should validate_inclusion_of(:status).in_array(Task::STATUSES) }
    it { should validate_inclusion_of(:priority).in_array(Task::PRIORITIES) }
  end

  describe "constants" do
    it "defines the expected statuses" do
      expect(Task::STATUSES).to eq(%w[backlog todo in_progress review done])
    end

    it "defines the expected priorities" do
      expect(Task::PRIORITIES).to eq(%w[low medium high urgent])
    end
  end

  describe "scopes" do
    let!(:open_task) { create(:task, status: "todo") }
    let!(:done_task) { create(:task, :done) }
    let(:agent)      { create(:agent) }
    let!(:assigned)  { create(:task, assigned_to_agent: agent) }

    describe ".open" do
      it "excludes done tasks" do
        expect(Task.open).to include(open_task, assigned)
        expect(Task.open).not_to include(done_task)
      end
    end

    describe ".done" do
      it "returns only done tasks" do
        expect(Task.done).to include(done_task)
        expect(Task.done).not_to include(open_task)
      end
    end

    describe ".for_agent" do
      it "returns tasks assigned to the given agent" do
        expect(Task.for_agent(agent)).to include(assigned)
        expect(Task.for_agent(agent)).not_to include(open_task)
      end
    end

    describe ".by_status" do
      it "filters by status" do
        expect(Task.by_status("todo")).to include(open_task)
        expect(Task.by_status("todo")).not_to include(done_task)
      end
    end

    describe ".by_priority" do
      it "orders urgent before high before medium before low" do
        low    = create(:task, priority: "low")
        medium = create(:task, priority: "medium")
        high   = create(:task, priority: "high")
        urgent = create(:task, :urgent)

        ordered = Task.by_priority.where(id: [low.id, medium.id, high.id, urgent.id])
        expect(ordered.map(&:priority)).to eq(%w[urgent high medium low])
      end
    end
  end

  describe "#assigned?" do
    it "returns false when no agent is assigned" do
      task = build(:task, assigned_to_agent: nil)
      expect(task.assigned?).to be false
    end

    it "returns true when an agent is assigned" do
      task = build(:task, assigned_to_agent: create(:agent))
      expect(task.assigned?).to be true
    end
  end

  describe "#add_comment" do
    let(:task) { create(:task) }

    it "appends a comment and saves the record" do
      task.add_comment(author_name: "Mando", body: "Working on it.")
      task.reload
      expect(task.comments.size).to eq(1)
      expect(task.comments.first["author"]).to eq("Mando")
      expect(task.comments.first["body"]).to eq("Working on it.")
      expect(task.comments.first["created_at"]).to be_present
    end

    it "preserves existing comments when adding a new one" do
      task.add_comment(author_name: "Mando", body: "First comment")
      task.add_comment(author_name: "Grogu", body: "Second comment")
      task.reload
      expect(task.comments.size).to eq(2)
    end

    it "returns the newly added comment hash" do
      result = task.add_comment(author_name: "Mando", body: "Details here")
      expect(result["author"]).to eq("Mando")
      expect(result["body"]).to eq("Details here")
      expect(result["created_at"]).to be_present
    end
  end

  describe "#overdue?" do
    it "returns true when due_at is in the past and status is not done" do
      task = build(:task, :overdue)
      expect(task.overdue?).to be true
    end

    it "returns false when status is done even if past due" do
      task = build(:task, due_at: 2.days.ago, status: "done")
      expect(task.overdue?).to be false
    end

    it "returns false when no due_at" do
      task = build(:task, due_at: nil)
      expect(task.overdue?).to be false
    end

    it "returns false when due_at is in the future" do
      task = build(:task, due_at: 2.days.from_now, status: "todo")
      expect(task.overdue?).to be false
    end
  end

  describe "#to_summary" do
    it "includes id, title, status, and priority" do
      task = create(:task, title: "Fix the bug", status: "in_progress", priority: "high")
      summary = task.to_summary
      expect(summary).to include("##{task.id}")
      expect(summary).to include("Fix the bug")
      expect(summary).to include("in_progress")
      expect(summary).to include("high")
    end

    it "includes assignee name when assigned" do
      agent = create(:agent, name: "Grogu")
      task  = create(:task, assigned_to_agent: agent)
      expect(task.to_summary).to include("Grogu")
    end

    it "includes formatted due date when present" do
      task = create(:task, due_at: Time.zone.parse("2025-12-31"))
      expect(task.to_summary).to include("2025-12-31")
    end

    it "omits assignment and due date when absent" do
      task = create(:task, assigned_to_agent: nil, due_at: nil)
      summary = task.to_summary
      expect(summary).not_to include("Assigned:")
      expect(summary).not_to include("Due:")
    end

    it "includes project title when linked" do
      project = create(:project)
      task    = create(:task, project: project)
      expect(task.to_summary).to include("Project: #{project.title}")
    end

    it "includes milestone title when linked" do
      project   = create(:project)
      milestone = create(:project_milestone, project: project)
      task      = create(:task, project_milestone: milestone)
      expect(task.to_summary).to include("Milestone: #{milestone.title}")
    end

    it "omits project and milestone when absent" do
      task = create(:task, project: nil, project_milestone: nil)
      expect(task.to_summary).not_to include("Project:")
      expect(task.to_summary).not_to include("Milestone:")
    end

    it "truncates long descriptions" do
      task = create(:task, description: "x" * 200)
      expect(task.to_summary).to include("Description:")
      expect(task.to_summary.length).to be < 400
    end
  end

  describe "completed_at lifecycle" do
    it "sets completed_at when moved to done" do
      task = create(:task, status: "todo")
      expect(task.completed_at).to be_nil
      task.update!(status: "done")
      expect(task.completed_at).to be_present
    end

    it "clears completed_at when moved out of done" do
      task = create(:task, :done)
      task.update!(status: "todo")
      expect(task.completed_at).to be_nil
    end

    it "sets completed_at when task is created directly as done" do
      task = create(:task, status: "done")
      expect(task.completed_at).to be_present
    end

    it "does not overwrite an existing completed_at if already done" do
      task = create(:task, status: "done")
      original_time = task.completed_at
      task.update!(title: "Retitled but still done")
      expect(task.completed_at).to be_within(1.second).of(original_time)
    end
  end

  describe "#dependencies_met?" do
    it "returns true when no dependencies" do
      task = create(:task)
      expect(task.dependencies_met?).to be true
    end

    it "returns false when blocking task is not done" do
      task_a = create(:task, status: "todo")
      task_b = create(:task, status: "in_progress")
      create(:task_dependency, task: task_b, depends_on: task_a)

      expect(task_b.dependencies_met?).to be false
    end

    it "returns true when all blocking tasks are done" do
      task_a = create(:task, :done)
      task_b = create(:task, status: "todo")
      create(:task_dependency, task: task_b, depends_on: task_a)

      expect(task_b.dependencies_met?).to be true
    end
  end

  describe "#blocked_by_dependencies?" do
    it "returns false with no dependencies" do
      task = create(:task)
      expect(task.blocked_by_dependencies?).to be false
    end

    it "returns true when blocked" do
      blocker = create(:task, status: "todo")
      task = create(:task)
      create(:task_dependency, task: task, depends_on: blocker)

      expect(task.blocked_by_dependencies?).to be true
    end
  end

  describe "checklist" do
    let(:task) { create(:task) }

    describe "#add_checklist_item" do
      it "adds an unchecked item" do
        task.add_checklist_item("Write tests")
        task.reload
        expect(task.checklist.size).to eq(1)
        expect(task.checklist.first["title"]).to eq("Write tests")
        expect(task.checklist.first["checked"]).to be false
      end
    end

    describe "#toggle_checklist_item" do
      before { task.add_checklist_item("Write tests") }

      it "toggles a checklist item" do
        task.toggle_checklist_item(0)
        task.reload
        expect(task.checklist[0]["checked"]).to be true
      end

      it "returns false for invalid index" do
        expect(task.toggle_checklist_item(99)).to be false
      end
    end

    describe "#checklist_complete?" do
      it "returns true when empty" do
        expect(task.checklist_complete?).to be true
      end

      it "returns false when items are unchecked" do
        task.add_checklist_item("Item 1")
        expect(task.checklist_complete?).to be false
      end

      it "returns true when all items are checked" do
        task.add_checklist_item("Item 1")
        task.toggle_checklist_item(0)
        expect(task.checklist_complete?).to be true
      end
    end
  end

  describe "#effective_hooks_for" do
    let(:task) { create(:task) }
    let(:skill) { create(:skill) }

    it "returns task-level hooks" do
      hook = create(:task_hook, task: task, skill: skill, trigger: "post", on_status: "done")
      expect(task.effective_hooks_for("done", "post")).to include(hook)
    end

    it "falls back to template hooks when no task-level hooks" do
      template = create(:task_template)
      template_hook = create(:task_hook, task_template: template, skill: skill, trigger: "post", on_status: "done")
      task.update!(task_template: template)

      expect(task.effective_hooks_for("done", "post")).to include(template_hook)
    end

    it "prefers task hooks over template hooks" do
      template = create(:task_template)
      create(:task_hook, task_template: template, skill: skill, trigger: "post", on_status: "done")
      task_hook = create(:task_hook, task: task, skill: skill, trigger: "post", on_status: "done")
      task.update!(task_template: template)

      hooks = task.effective_hooks_for("done", "post")
      expect(hooks).to include(task_hook)
      expect(hooks.size).to eq(1)
    end

    it "returns empty when no hooks match" do
      expect(task.effective_hooks_for("done", "pre")).to be_empty
    end
  end

  describe "#apply_template!" do
    it "sets template and priority" do
      template = create(:task_template, default_priority: "high")
      task = build(:task)
      task.apply_template!(template)

      expect(task.task_template).to eq(template)
      expect(task.priority).to eq("high")
    end
  end
end
