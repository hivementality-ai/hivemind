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

      it "lists supported actions in the error" do
        result = subject.call
        expect(result.error).to include("create")
        expect(result.error).to include("close")
      end
    end

    context "with empty action" do
      let(:input) { { "action" => "" } }

      it "returns a failure" do
        expect(subject.call).not_to be_success
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

      it "silently ignores invalid status and falls back to backlog" do
        input["status"] = "limbo"
        subject.call
        expect(Task.last.status).to eq("backlog")
      end

      it "silently ignores invalid priority and falls back to medium" do
        input["priority"] = "kinda_urgent"
        subject.call
        expect(Task.last.priority).to eq("medium")
      end

      it "stores a description when provided" do
        input["description"] = "This is the description"
        subject.call
        expect(Task.last.description).to eq("This is the description")
      end

      it "parses and stores due_at when provided" do
        input["due_at"] = "2025-12-31"
        subject.call
        expect(Task.last.due_at).to be_present
      end

      it "ignores unparseable due_at without failing" do
        input["due_at"] = "not-a-date"
        result = subject.call
        expect(result).to be_success
        expect(Task.last.due_at).to be_nil
      end

      context "when assign_to is provided and agent exists" do
        let!(:assignee) { create(:agent, name: "Grogu") }

        it "assigns the task to the named agent" do
          input["assign_to"] = "Grogu"
          subject.call
          expect(Task.last.assigned_to_agent).to eq(assignee)
        end
      end

      context "when assign_to names a nonexistent agent" do
        it "returns failure without creating a task" do
          input["assign_to"] = "GhostAgent"
          expect { subject.call }.not_to change(Task, :count)
          expect(subject.call).not_to be_success
        end
      end

      context "when title is missing" do
        let(:input) { { "action" => "create" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("title is required")
        end
      end

      context "when title is blank whitespace" do
        let(:input) { { "action" => "create", "title" => "   " } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
        end
      end
    end

    # ─── update ───────────────────────────────────────────────────

    context "action: update" do
      let!(:task) { create(:task, title: "Original", priority: "medium") }
      let(:input) { { "action" => "update", "task_id" => task.id.to_s, "title" => "Updated title" } }

      it "updates the title" do
        subject.call
        expect(task.reload.title).to eq("Updated title")
      end

      it "returns success mentioning the updated title" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Updated title")
      end

      it "updates priority when provided" do
        input["priority"] = "urgent"
        subject.call
        expect(task.reload.priority).to eq("urgent")
      end

      it "ignores invalid priority and leaves existing value unchanged" do
        input["priority"] = "bananas"
        subject.call
        expect(task.reload.priority).to eq("medium")
      end

      it "clears due_at when passed an empty string" do
        task.update!(due_at: 1.day.from_now)
        input["due_at"] = ""
        subject.call
        expect(task.reload.due_at).to be_nil
      end

      it "updates description to empty string when key is present with empty value" do
        task.update!(description: "Old description")
        input["description"] = ""
        subject.call
        expect(task.reload.description).to eq("")
      end

      context "when task_id is missing" do
        let(:input) { { "action" => "update" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("task_id is required")
        end
      end

      context "when task does not exist" do
        let(:input) { { "action" => "update", "task_id" => "99999", "title" => "Whatever" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
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

      it "sets completed_at when moved to done" do
        input["status"] = "done"
        subject.call
        expect(task.reload.completed_at).to be_present
      end

      context "with invalid status" do
        let(:input) { { "action" => "move", "task_id" => task.id.to_s, "status" => "flying" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("Invalid status")
        end

        it "does not change the task status" do
          subject.call
          expect(task.reload.status).to eq("backlog")
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

      context "when status param is missing" do
        let(:input) { { "action" => "move", "task_id" => task.id.to_s } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("status is required")
        end
      end
    end

    # ─── assign ───────────────────────────────────────────────────

    context "action: assign" do
      let!(:assignee) { create(:agent, name: "Grogu") }
      let!(:task)     { create(:task) }
      let(:input)    { { "action" => "assign", "task_id" => task.id.to_s, "assign_to" => "Grogu" } }

      it "assigns the task to the named agent" do
        subject.call
        expect(task.reload.assigned_to_agent).to eq(assignee)
      end

      it "returns success mentioning the assignee name" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Grogu")
      end

      context "when looking up agent by slug" do
        let(:slugged) { create(:agent, name: "BySlug") }

        it "finds the agent by slug" do
          input["assign_to"] = slugged.slug
          subject.call
          expect(task.reload.assigned_to_agent).to eq(slugged)
        end
      end

      context "when agent not found" do
        let(:input) { { "action" => "assign", "task_id" => task.id.to_s, "assign_to" => "NoSuchAgent" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
        end

        it "does not change the assigned agent" do
          subject.call
          expect(task.reload.assigned_to_agent_id).to be_nil
        end
      end

      context "when assign_to param is missing" do
        let(:input) { { "action" => "assign", "task_id" => task.id.to_s } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("assign_to is required")
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

      it "filters by priority when provided" do
        create(:task, :urgent, status: "backlog")
        input["priority"] = "urgent"
        result = subject.call
        expect(result.data[:output]).to include("Tasks (1)")
      end

      it "filters by assigned_to when provided" do
        target = create(:agent, name: "Filter Me")
        create(:task, assigned_to_agent: target, status: "todo")
        input["assigned_to"] = "Filter Me"
        result = subject.call
        expect(result.data[:output]).to include("Tasks (1)")
      end

      it "returns 'No tasks found' when nothing matches" do
        Task.delete_all
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No tasks found")
      end

      it "respects a custom limit" do
        input["limit"] = "2"
        result = subject.call
        expect(result.data[:output]).to include("Tasks (2)")
      end

      it "clamps limit to 50 maximum" do
        input["limit"] = "999"
        result = subject.call
        # 4 tasks exist — should not raise and returns all within clamp
        expect(result).to be_success
      end

      context "when assigned_to names a nonexistent agent" do
        it "returns failure" do
          input["assigned_to"] = "GhostAgent"
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
        end
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

      it "returns a friendly message when agent has no open tasks" do
        mine.update!(status: "done")
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("no open tasks")
      end

      context "when executor has no agent context" do
        subject { described_class.new(input: input, config: {}, agent: nil) }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("No agent context")
        end
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

      it "uses 'Unknown' as author when agent is nil" do
        executor = described_class.new(input: input, config: {}, agent: nil)
        executor.call
        expect(task.reload.comments.first["author"]).to eq("Unknown")
      end

      context "when text is missing" do
        let(:input) { { "action" => "add_comment", "task_id" => task.id.to_s } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("text is required")
        end
      end

      context "when task_id is missing" do
        let(:input) { { "action" => "add_comment", "text" => "orphan comment" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("task_id is required")
        end
      end

      context "when task does not exist" do
        let(:input) { { "action" => "add_comment", "task_id" => "99999", "text" => "ghost" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
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

      it "returns error when task is already done" do
        task.update!(status: "done")
        result = subject.call
        expect(result).not_to be_success
        expect(result.error).to include("already")
      end

      context "when task_id is missing" do
        let(:input) { { "action" => "close" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("task_id is required")
        end
      end

      context "when task does not exist" do
        let(:input) { { "action" => "close", "task_id" => "99999" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
        end
      end
    end

    # ─── add_dependency ──────────────────────────────────────────

    context "action: add_dependency" do
      let!(:task_a) { create(:task, title: "Task A") }
      let!(:task_b) { create(:task, title: "Task B") }
      let(:input) { { "action" => "add_dependency", "task_id" => task_b.id.to_s, "depends_on_task_id" => task_a.id.to_s } }

      it "creates a dependency" do
        expect { subject.call }.to change(TaskDependency, :count).by(1)
      end

      it "returns success" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include(task_a.id.to_s)
      end

      it "logs an event" do
        expect { subject.call }.to change(TaskEvent, :count).by(1)
      end
    end

    # ─── remove_dependency ───────────────────────────────────────

    context "action: remove_dependency" do
      let!(:task_a) { create(:task) }
      let!(:task_b) { create(:task) }
      let!(:dep)    { create(:task_dependency, task: task_b, depends_on: task_a) }
      let(:input)   { { "action" => "remove_dependency", "task_id" => task_b.id.to_s, "depends_on_task_id" => task_a.id.to_s } }

      it "removes the dependency" do
        expect { subject.call }.to change(TaskDependency, :count).by(-1)
      end

      it "returns success" do
        result = subject.call
        expect(result).to be_success
      end
    end

    # ─── update_checklist ────────────────────────────────────────

    context "action: update_checklist" do
      let!(:task) { create(:task) }

      context "add item" do
        let(:input) { { "action" => "update_checklist", "task_id" => task.id.to_s, "checklist_action" => "add", "item_title" => "Write tests" } }

        it "adds a checklist item" do
          subject.call
          task.reload
          expect(task.checklist.size).to eq(1)
          expect(task.checklist.first["title"]).to eq("Write tests")
        end

        it "returns success" do
          result = subject.call
          expect(result).to be_success
        end
      end

      context "toggle item" do
        before { task.add_checklist_item("Write tests") }

        let(:input) { { "action" => "update_checklist", "task_id" => task.id.to_s, "checklist_action" => "toggle", "item_index" => "0" } }

        it "toggles the checklist item" do
          subject.call
          task.reload
          expect(task.checklist[0]["checked"]).to be true
        end
      end

      context "invalid sub-action" do
        let(:input) { { "action" => "update_checklist", "task_id" => task.id.to_s, "checklist_action" => "delete" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("Unknown checklist_action")
        end
      end
    end

    # ─── add_hook ────────────────────────────────────────────────

    context "action: add_hook" do
      let!(:task)  { create(:task) }
      let!(:skill) { create(:skill, name: "review_skill") }
      let(:input) do
        {
          "action" => "add_hook",
          "task_id" => task.id.to_s,
          "skill_name" => "review_skill",
          "hook_trigger" => "post",
          "hook_on_status" => "done"
        }
      end

      it "creates a hook on the task" do
        expect { subject.call }.to change(TaskHook, :count).by(1)
      end

      it "returns success" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("review_skill")
      end

      context "when skill not found" do
        let(:input) { { "action" => "add_hook", "task_id" => task.id.to_s, "skill_name" => "nope", "hook_trigger" => "post", "hook_on_status" => "done" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
        end
      end
    end

    # ─── remove_hook ─────────────────────────────────────────────

    context "action: remove_hook" do
      let!(:task)  { create(:task) }
      let!(:skill) { create(:skill) }
      let!(:hook)  { create(:task_hook, task: task, skill: skill, trigger: "post", on_status: "done") }
      let(:input)  { { "action" => "remove_hook", "task_id" => task.id.to_s, "hook_id" => hook.id.to_s } }

      it "removes the hook" do
        expect { subject.call }.to change(TaskHook, :count).by(-1)
      end

      it "returns success" do
        result = subject.call
        expect(result).to be_success
      end
    end

    # ─── add_artifact ──────────────────────────────────────────────

    context "action: add_artifact" do
      let!(:task) { create(:task) }
      let(:input) do
        {
          "action" => "add_artifact",
          "task_id" => task.id.to_s,
          "title" => "auth_service.rb",
          "type" => "code",
          "content" => "class AuthService; end"
        }
      end

      it "adds an artifact to the task" do
        subject.call
        task.reload
        expect(task.artifacts.size).to eq(1)
        expect(task.artifacts.first["title"]).to eq("auth_service.rb")
      end

      it "sets the created_by to the agent name" do
        subject.call
        task.reload
        expect(task.artifacts.first["created_by"]).to eq("Mando")
      end

      it "returns success mentioning the artifact title" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("auth_service.rb")
      end

      it "logs an event" do
        expect { subject.call }.to change(TaskEvent, :count).by(1)
      end

      it "defaults type to document when not provided" do
        input.delete("type")
        subject.call
        task.reload
        expect(task.artifacts.first["type"]).to eq("document")
      end

      context "without content" do
        before { input.delete("content") }

        it "creates artifact without content" do
          result = subject.call
          expect(result).to be_success
          task.reload
          expect(task.artifacts.first["content"]).to be_nil
        end
      end

      context "when title is missing" do
        let(:input) { { "action" => "add_artifact", "task_id" => task.id.to_s } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("title is required")
        end
      end

      context "when task_id is missing" do
        let(:input) { { "action" => "add_artifact", "title" => "orphan" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("task_id is required")
        end
      end

      context "when task does not exist" do
        let(:input) { { "action" => "add_artifact", "task_id" => "99999", "title" => "ghost" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
        end
      end
    end

    # ─── remove_artifact ─────────────────────────────────────────

    context "action: remove_artifact" do
      let!(:task) { create(:task) }
      let!(:artifact) { task.add_artifact(type: "code", title: "old.rb", created_by: "Mando") }
      let(:input) { { "action" => "remove_artifact", "task_id" => task.id.to_s, "artifact_id" => artifact["id"] } }

      it "removes the artifact" do
        subject.call
        task.reload
        expect(task.artifacts.size).to eq(0)
      end

      it "returns success" do
        result = subject.call
        expect(result).to be_success
      end

      it "logs an event" do
        expect { subject.call }.to change(TaskEvent, :count).by(1)
      end

      context "when artifact_id does not match" do
        let(:input) { { "action" => "remove_artifact", "task_id" => task.id.to_s, "artifact_id" => "bad-uuid" } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("not found")
        end
      end

      context "when artifact_id is missing" do
        let(:input) { { "action" => "remove_artifact", "task_id" => task.id.to_s } }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("artifact_id is required")
        end
      end
    end

    # ─── add_hook with team-level (no task_id) ───────────────────

    context "action: add_hook (team-level)" do
      let(:team) { create(:team) }
      let(:agent) { create(:agent, name: "Mando", team: team) }

      let(:input) do
        {
          "action" => "add_hook",
          "hook_trigger" => "post",
          "hook_on_status" => "in_progress"
        }
      end

      it "creates a team-level hook without a skill" do
        expect { subject.call }.to change(TaskHook, :count).by(1)
        hook = TaskHook.last
        expect(hook.team).to eq(team)
        expect(hook.task).to be_nil
        expect(hook.skill).to be_nil
      end

      it "returns success mentioning default behavior" do
        result = subject.call
        expect(result).to be_success
        expect(result.data[:output]).to include("default behavior")
      end

      context "when agent has no team" do
        let(:agent) { create(:agent, name: "Mando", team: nil) }

        it "returns failure" do
          result = subject.call
          expect(result).not_to be_success
          expect(result.error).to include("No team found")
        end
      end
    end

    # ─── create with template ────────────────────────────────────

    context "action: create with template" do
      let!(:template) { create(:task_template, name: "bug_report", default_priority: "high") }
      let(:input) { { "action" => "create", "title" => "Fix login bug", "template" => "bug_report" } }

      it "applies the template to the task" do
        subject.call
        task = Task.last
        expect(task.task_template).to eq(template)
        expect(task.priority).to eq("high")
      end
    end

    # ─── create with checklist ───────────────────────────────────

    context "action: create with checklist" do
      let(:input) { { "action" => "create", "title" => "Deploy app", "checklist" => [ "Build image", "Run migrations", "Verify health" ] } }

      it "creates task with checklist items" do
        subject.call
        task = Task.last
        expect(task.checklist.size).to eq(3)
        expect(task.checklist.map { |i| i["title"] }).to eq([ "Build image", "Run migrations", "Verify health" ])
        expect(task.checklist.all? { |i| i["checked"] == false }).to be true
      end
    end
  end
end
