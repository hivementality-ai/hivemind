# frozen_string_literal: true

require "rails_helper"

RSpec.describe Task, type: :model do
  let(:team) { create(:team) }
  let(:user) { create(:user) }

  describe "validations" do
    it "is valid with required attributes" do
      task = build(:task, team: team, user: user)
      expect(task).to be_valid
    end

    it "requires a title" do
      task = build(:task, team: team, user: user, title: "")
      expect(task).not_to be_valid
      expect(task.errors[:title]).to be_present
    end

    it "requires a team" do
      task = build(:task, user: user, team: nil)
      expect(task).not_to be_valid
    end

    it "requires a user" do
      task = build(:task, team: team, user: nil)
      expect(task).not_to be_valid
    end

    it "allows nil agent (unassigned)" do
      task = build(:task, team: team, user: user, agent: nil)
      expect(task).to be_valid
    end

    it "allows nil project and milestone" do
      task = build(:task, team: team, user: user, project: nil, project_milestone: nil)
      expect(task).to be_valid
    end

    context "milestone/project consistency" do
      let(:project_a) { create(:project, team: team, user: user) }
      let(:project_b) { create(:project, team: team, user: user) }
      let(:milestone_a) { create(:project_milestone, project: project_a) }

      it "is valid when milestone belongs to the given project" do
        task = build(:task, team: team, user: user, project: project_a, project_milestone: milestone_a)
        expect(task).to be_valid
      end

      it "is invalid when milestone belongs to a different project" do
        task = build(:task, team: team, user: user, project: project_b, project_milestone: milestone_a)
        expect(task).not_to be_valid
        expect(task.errors[:project_milestone]).to be_present
      end
    end
  end

  describe "enums" do
    it "defaults status to todo" do
      task = create(:task, team: team, user: user)
      expect(task.status).to eq("todo")
    end

    it "defaults priority to medium" do
      task = create(:task, team: team, user: user)
      expect(task.priority).to eq("medium")
    end

    it "supports all expected statuses" do
      %w[backlog todo in_progress review done cancelled].each do |s|
        task = build(:task, team: team, user: user, status: s)
        expect(task).to be_valid, "expected status '#{s}' to be valid"
      end
    end

    it "supports all expected priorities" do
      %w[low medium high urgent].each do |p|
        task = build(:task, team: team, user: user, priority: p)
        expect(task).to be_valid, "expected priority '#{p}' to be valid"
      end
    end
  end

  describe "scopes" do
    let!(:todo_task)        { create(:task, team: team, user: user, status: :todo) }
    let!(:in_progress_task) { create(:task, team: team, user: user, status: :in_progress) }
    let!(:done_task)        { create(:task, team: team, user: user, status: :done) }
    let!(:cancelled_task)   { create(:task, team: team, user: user, status: :cancelled) }
    let(:agent)             { create(:agent, :with_team, team: team) }
    let!(:assigned_task)    { create(:task, team: team, user: user, agent: agent) }

    describe ".active" do
      it "excludes done and cancelled tasks" do
        active = Task.active
        expect(active).to include(todo_task, in_progress_task)
        expect(active).not_to include(done_task, cancelled_task)
      end
    end

    describe ".by_status" do
      it "filters by status" do
        expect(Task.by_status(:todo)).to include(todo_task)
        expect(Task.by_status(:todo)).not_to include(in_progress_task)
      end
    end

    describe ".assigned_to" do
      it "returns tasks assigned to the given agent" do
        expect(Task.assigned_to(agent)).to include(assigned_task)
        expect(Task.assigned_to(agent)).not_to include(todo_task)
      end
    end

    describe ".unassigned" do
      it "returns tasks with no agent" do
        expect(Task.unassigned).to include(todo_task)
        expect(Task.unassigned).not_to include(assigned_task)
      end
    end

    describe ".overdue" do
      let!(:overdue_task) { create(:task, :overdue, team: team, user: user) }

      it "includes overdue tasks" do
        expect(Task.overdue).to include(overdue_task)
      end

      it "excludes done tasks even if past due" do
        past_due_done = create(:task, team: team, user: user, due_date: 2.days.ago, status: :done)
        expect(Task.overdue).not_to include(past_due_done)
      end
    end

    describe ".for_team" do
      let(:other_team) { create(:team) }
      let!(:other_task) { create(:task, team: other_team, user: user) }

      it "scopes to the given team" do
        expect(Task.for_team(team)).not_to include(other_task)
        expect(Task.for_team(other_team)).to include(other_task)
      end
    end
  end

  describe "callbacks" do
    describe "completed_at on done" do
      it "sets completed_at when moved to done" do
        task = create(:task, team: team, user: user, status: :todo)
        expect(task.completed_at).to be_nil

        task.update!(status: :done)
        expect(task.reload.completed_at).to be_present
      end

      it "does not overwrite completed_at if already set" do
        original_time = 1.hour.ago
        task = create(:task, team: team, user: user, status: :done, completed_at: original_time)
        task.update!(priority: :high)
        expect(task.reload.completed_at).to be_within(1.second).of(original_time)
      end
    end
  end

  describe "associations" do
    it "belongs to team" do
      expect(described_class.reflect_on_association(:team).macro).to eq(:belongs_to)
    end

    it "belongs to user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "optionally belongs to agent" do
      reflection = described_class.reflect_on_association(:agent)
      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.options[:optional]).to be true
    end

    it "optionally belongs to project" do
      reflection = described_class.reflect_on_association(:project)
      expect(reflection.options[:optional]).to be true
    end

    it "optionally belongs to project_milestone" do
      reflection = described_class.reflect_on_association(:project_milestone)
      expect(reflection.options[:optional]).to be true
    end

    it "optionally belongs to session" do
      reflection = described_class.reflect_on_association(:session)
      expect(reflection.options[:optional]).to be true
    end
  end
end
