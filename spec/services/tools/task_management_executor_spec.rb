# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::TaskManagementExecutor, type: :service do
  let(:team)  { create(:team) }
  let(:user)  { create(:user) }
  let(:agent) { create(:agent, :with_team, team: team) }

  def executor(input, calling_agent = agent)
    described_class.new(input: input, config: {}, agent: calling_agent)
  end

  describe "missing action" do
    it "returns failure when action is blank" do
      result = executor({}).call
      expect(result).not_to be_success
      expect(result.error).to include("action is required")
    end

    it "returns failure for unknown action" do
      result = executor({ "action" => "explode" }).call
      expect(result).not_to be_success
      expect(result.error).to include("Unknown action")
    end
  end

  describe "create_task" do
    it "creates a task and returns formatted output" do
      result = executor({ "action" => "create_task", "title" => "Deploy auth" }).call
      expect(result).to be_success
      expect(result.data[:output]).to include("Created task")
      expect(result.data[:output]).to include("Deploy auth")
      expect(Task.last.title).to eq("Deploy auth")
    end

    it "sets created_by to agent slug" do
      executor({ "action" => "create_task", "title" => "Test task" }).call
      expect(Task.last.created_by).to eq("agent:#{agent.slug}")
    end

    it "sets created_by_agent" do
      executor({ "action" => "create_task", "title" => "Test task" }).call
      expect(Task.last.created_by_agent).to eq(agent)
    end

    it "sets priority when provided" do
      executor({ "action" => "create_task", "title" => "Urgent task", "priority" => "urgent" }).call
      expect(Task.last.priority).to eq("urgent")
    end

    it "defaults to medium priority" do
      executor({ "action" => "create_task", "title" => "Normal task" }).call
      expect(Task.last.priority).to eq("medium")
    end

    it "rejects invalid priority" do
      result = executor({ "action" => "create_task", "title" => "Bad prio", "priority" => "critical" }).call
      expect(result).not_to be_success
      expect(result.error).to include("Invalid priority")
    end

    it "assigns to named agent on same team" do
      assignee = create(:agent, :with_team, team: team)
      executor({ "action" => "create_task", "title" => "Delegated", "assign_to" => assignee.name }).call
      expect(Task.last.agent).to eq(assignee)
    end

    it "rejects assigning to unknown agent" do
      result = executor({ "action" => "create_task", "title" => "Fail", "assign_to" => "ghost_agent" }).call
      expect(result).not_to be_success
      expect(result.error).to include("not found on this team")
    end

    it "fails without title" do
      result = executor({ "action" => "create_task", "title" => "" }).call
      expect(result).not_to be_success
      expect(result.error).to include("title is required")
    end

    it "fails when agent has no team" do
      homeless_agent = create(:agent)
      result = executor({ "action" => "create_task", "title" => "Teamless" }, homeless_agent).call
      expect(result).not_to be_success
      expect(result.error).to include("no team")
    end

    it "accepts legacy 'create' action alias" do
      result = executor({ "action" => "create", "title" => "Legacy create" }).call
      expect(result).to be_success
    end
  end

  describe "move_task" do
    let!(:task) { create(:task, team: team, user: user, status: :todo) }

    it "moves task to new status" do
      executor({ "action" => "move_task", "task_id" => task.id, "status" => "in_progress" }).call
      expect(task.reload.status).to eq("in_progress")
    end

    it "returns success with updated task info" do
      result = executor({ "action" => "move_task", "task_id" => task.id, "status" => "review" }).call
      expect(result).to be_success
      expect(result.data[:output]).to include("moved to review")
    end

    it "rejects invalid status" do
      result = executor({ "action" => "move_task", "task_id" => task.id, "status" => "limbo" }).call
      expect(result).not_to be_success
      expect(result.error).to include("Invalid status")
    end

    it "fails when status is blank" do
      result = executor({ "action" => "move_task", "task_id" => task.id, "status" => "" }).call
      expect(result).not_to be_success
    end

    it "sets completed_at when moving to done" do
      executor({ "action" => "move_task", "task_id" => task.id, "status" => "done" }).call
      expect(task.reload.completed_at).to be_present
    end

    it "returns not found for missing task" do
      result = executor({ "action" => "move_task", "task_id" => 999_999, "status" => "done" }).call
      expect(result).not_to be_success
      expect(result.error).to include("Not found")
    end
  end

  describe "assign_task" do
    let!(:task)     { create(:task, team: team, user: user, agent: nil) }
    let!(:assignee) { create(:agent, :with_team, team: team) }

    it "assigns to named agent" do
      executor({ "action" => "assign_task", "task_id" => task.id, "agent_name" => assignee.name }).call
      expect(task.reload.agent).to eq(assignee)
    end

    it "self-assigns with 'me'" do
      executor({ "action" => "assign_task", "task_id" => task.id, "agent_name" => "me" }).call
      expect(task.reload.agent).to eq(agent)
    end

    it "unassigns with 'unassign'" do
      task.update!(agent: agent)
      executor({ "action" => "assign_task", "task_id" => task.id, "agent_name" => "unassign" }).call
      expect(task.reload.agent).to be_nil
    end

    it "rejects agent from different team" do
      other_agent = create(:agent, :with_team)
      result = executor({ "action" => "assign_task", "task_id" => task.id, "agent_name" => other_agent.name }).call
      expect(result).not_to be_success
      expect(result.error).to include("not found on team")
    end
  end

  describe "list_tasks" do
    let!(:high_task) { create(:task, team: team, user: user, priority: :high) }
    let!(:low_task)  { create(:task, team: team, user: user, priority: :low) }
    let!(:done_task) { create(:task, team: team, user: user, status: :done) }

    it "returns active tasks by default" do
      result = executor({ "action" => "list_tasks" }).call
      expect(result).to be_success
      expect(result.data[:output]).to include(high_task.title)
      expect(result.data[:output]).not_to include(done_task.title)
    end

    it "filters by status" do
      result = executor({ "action" => "list_tasks", "status" => "done" }).call
      expect(result.data[:output]).to include(done_task.title)
      expect(result.data[:output]).not_to include(high_task.title)
    end

    it "filters by agent" do
      assigned = create(:task, team: team, user: user, agent: agent)
      result = executor({ "action" => "list_tasks", "agent" => agent.name }).call
      expect(result.data[:output]).to include(assigned.title)
      expect(result.data[:output]).not_to include(high_task.title)
    end

    it "returns 'No tasks found' when empty" do
      Task.delete_all
      result = executor({ "action" => "list_tasks" }).call
      expect(result.data[:output]).to eq("No tasks found.")
    end

    it "supports legacy 'list' alias" do
      result = executor({ "action" => "list" }).call
      expect(result).to be_success
    end
  end

  describe "my_tasks" do
    it "returns tasks assigned to calling agent" do
      my_task    = create(:task, team: team, user: user, agent: agent)
      other_task = create(:task, team: team, user: user, agent: nil)

      result = executor({ "action" => "my_tasks" }).call
      expect(result).to be_success
      expect(result.data[:output]).to include(my_task.title)
      expect(result.data[:output]).not_to include(other_task.title)
    end

    it "notes overdue count in header" do
      create(:task, :overdue, team: team, user: user, agent: agent)
      result = executor({ "action" => "my_tasks" }).call
      expect(result.data[:output]).to include("overdue")
    end

    it "returns empty message when no tasks" do
      result = executor({ "action" => "my_tasks" }).call
      expect(result.data[:output]).to include("No tasks assigned")
    end
  end

  describe "add_comment" do
    let!(:task) { create(:task, team: team, user: user) }

    it "appends comment to metadata" do
      executor({ "action" => "add_comment", "task_id" => task.id, "comment" => "Working on it" }).call
      comments = task.reload.metadata["comments"]
      expect(comments).to be_present
      expect(comments.last["text"]).to eq("Working on it")
      expect(comments.last["agent_name"]).to eq(agent.name)
    end

    it "fails when comment is blank" do
      result = executor({ "action" => "add_comment", "task_id" => task.id, "comment" => "" }).call
      expect(result).not_to be_success
      expect(result.error).to include("comment is required")
    end
  end

  describe "close_task" do
    let!(:task) { create(:task, team: team, user: user, status: :in_progress) }

    it "sets status to done" do
      executor({ "action" => "close_task", "task_id" => task.id }).call
      expect(task.reload.status).to eq("done")
    end

    it "stores resolution note as comment" do
      executor({ "action" => "close_task", "task_id" => task.id, "resolution_note" => "All done!" }).call
      comments = task.reload.metadata["comments"]
      expect(comments.last["text"]).to include("All done!")
    end

    it "supports legacy 'close' alias" do
      result = executor({ "action" => "close", "task_id" => task.id }).call
      expect(result).to be_success
    end
  end

  describe "update_task" do
    let!(:task) { create(:task, team: team, user: user, title: "Original", priority: :medium) }

    it "updates title" do
      executor({ "action" => "update_task", "task_id" => task.id, "title" => "Updated" }).call
      expect(task.reload.title).to eq("Updated")
    end

    it "updates priority" do
      executor({ "action" => "update_task", "task_id" => task.id, "priority" => "urgent" }).call
      expect(task.reload.priority).to eq("urgent")
    end

    it "fails when no fields provided" do
      result = executor({ "action" => "update_task", "task_id" => task.id }).call
      expect(result).not_to be_success
      expect(result.error).to include("No fields to update")
    end

    it "supports legacy 'update' alias" do
      result = executor({ "action" => "update", "task_id" => task.id, "title" => "Updated via legacy" }).call
      expect(result).to be_success
    end
  end
end
