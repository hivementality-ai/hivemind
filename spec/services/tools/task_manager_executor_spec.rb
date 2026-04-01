# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::TaskManagerExecutor do
  subject { described_class.new(input: input, config: {}, agent: agent) }

  let(:agent) { create(:agent, name: "Mando") }

  describe "#call" do
    context "with unknown action" do
      let(:input) { { "action" => "explode" } }

      it "returns a failure" do
        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to include("Unknown action")
      end
    end

    # ─── create ──────────────────────────────────────────────────

    context "action: create" do
      let(:input) { { "action" => "create", "title" => "Fix the null pointer" } }

      it "creates a task and returns success" do
        expect { subject.call }.to change(Task, :count).by(1)
      end

      it "sets the created_by_agent" do
        subject.call
        expect(Task.last.created_by_agent).to eq(agent)
      end

      it "returns the task id in output" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Fix the null pointer")
      end

      it "applies default status and priority" do
        subject.call
        task = Task.last
        expect(task.status).to eq("backlog")
        expect(task.priority).to eq("medium")
      end

      it "applies provided status and priority" do
        input.merge!("status" => "todo", "priority" => "urgent")
        subject.call
        task = Task.last
        expect(task.status).to eq("todo")
        expect(task.priority).to eq("urgent")
      end

      context "when title is missing" do
        let(:input) { { "action" => "create" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("title is required")
        end
      end
    end

    # ─── move ─────────────────────────────────────────────────────

    context "action: move" do
      let!(:task)  { create(:task, status: "backlog") }
      let(:input)  { { "action" => "move", "task_id" => task.id.to_s, "status" => "in_progress" } }

      it "updates the task status" do
        subject.call
        expect(task.reload.status).to eq("in_progress")
      end

      it "returns success with old and new status" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("backlog")
        expect(result.data[:output]).to include("in_progress")
      end

      context "with invalid status" do
        let(:input) { { "action" => "move", "task_id" => task.id.to_s, "status" => "flying" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("Invalid status")
        end
      end

      context "when task not found" do
        let(:input) { { "action" => "move", "task_id" => "99999", "status" => "todo" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
        end
      end
    end

    # ─── assign ───────────────────────────────────────────────────

    context "action: assign" do
      let(:assignee) { create(:agent, name: "Grogu") }
      let!(:task)    { create(:task) }
      let(:input)    { { "action" => "assign", "task_id" => task.id.to_s, "assign_to" => "Grogu" } }

      it "assigns the task to the named agent" do
        subject.call
        expect(task.reload.assigned_to_agent).to eq(assignee)
      end

      it "returns success" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Grogu")
      end

      context "when agent not found" do
        let(:input) { { "action" => "assign", "task_id" => task.id.to_s, "assign_to" => "NoSuchAgent" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
        end
      end
    end

    # ─── list ─────────────────────────────────────────────────────

    context "action: list" do
      let(:input) { { "action" => "list" } }

      before do
        create_list(:task, 3, status: "todo")
        create(:task, :done)
      end

      it "returns all tasks by default" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Tasks (4)")
      end

      it "filters by status when provided" do
        input["status"] = "todo"
        result = subject.call
        expect(result.data[:output]).to include("Tasks (3)")
      end
    end

    # ─── my_tasks ─────────────────────────────────────────────────

    context "action: my_tasks" do
      let(:input)   { { "action" => "my_tasks" } }
      let!(:mine)   { create(:task, assigned_to_agent: agent, status: "todo") }
      let!(:others) { create(:task, status: "todo") }
      let!(:done)   { create(:task, :done, assigned_to_agent: agent) }

      it "returns only open tasks assigned to the current agent" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include(mine.title)
        expect(result.data[:output]).not_to include(others.title)
        expect(result.data[:output]).not_to include(done.title)
      end
    end

    # ─── add_comment ──────────────────────────────────────────────

    context "action: add_comment" do
      let!(:task) { create(:task) }
      let(:input) { { "action" => "add_comment", "task_id" => task.id.to_s, "text" => "Looks good to me" } }

      it "adds a comment authored by the agent" do
        subject.call
        task.reload
        expect(task.comments.size).to eq(1)
        expect(task.comments.first["author"]).to eq("Mando")
        expect(task.comments.first["body"]).to eq("Looks good to me")
      end

      it "returns success" do
        result = subject.call
        expect(result).to be_success
      end

      context "when text is missing" do
        let(:input) { { "action" => "add_comment", "task_id" => task.id.to_s } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
        end
      end
    end

    # ─── close ────────────────────────────────────────────────────

    context "action: close" do
      let!(:task) { create(:task, status: "review") }
      let(:input) { { "action" => "close", "task_id" => task.id.to_s } }

      it "sets status to done" do
        subject.call
        expect(task.reload.status).to eq("done")
      end

      it "sets completed_at" do
        subject.call
        expect(task.reload.completed_at).to be_present
      end
    end
  end
end
