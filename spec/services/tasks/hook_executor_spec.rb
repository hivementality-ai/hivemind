# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::HookExecutor do
  let(:agent) { create(:agent) }
  let(:skill) { create(:skill, content: "Do the thing") }
  let(:task) { create(:task, title: "Test Task", assigned_to_agent: agent) }
  let(:hook) { create(:task_hook, :post, task: task, skill: skill, on_status: "done") }

  describe ".call" do
    it "creates a session and enqueues ChatStreamJob" do
      expect {
        result = described_class.call(hook: hook, task: task, agent: agent)
        expect(result).to be_success
        expect(result.data[:session_id]).to be_present
      }.to have_enqueued_job(ChatStreamJob)
    end

    it "creates a task_event for the hook execution" do
      expect {
        described_class.call(hook: hook, task: task, agent: agent)
      }.to change(TaskEvent, :count).by(1)

      event = TaskEvent.last
      expect(event.event_type).to eq("hook_fired")
      expect(event.summary).to include(skill.name)
    end

    it "creates a session with correct metadata" do
      result = described_class.call(hook: hook, task: task, agent: agent)
      session = Session.find(result.data[:session_id])

      expect(session.metadata["type"]).to eq("task_hook")
      expect(session.metadata["task_id"]).to eq(task.id)
      expect(session.metadata["hook_id"]).to eq(hook.id)
    end

    it "fails when no agent is available" do
      agentless_task = create(:task, assigned_to_agent: nil, created_by_agent: nil)
      agentless_hook = create(:task_hook, :post, task: agentless_task, skill: skill, on_status: "done")

      result = described_class.call(hook: agentless_hook, task: agentless_task)
      expect(result).not_to be_success
      expect(result.error).to include("No agent available")
    end

    it "uses assigned agent from task when no agent passed" do
      result = described_class.call(hook: hook, task: task)
      session = Session.find(result.data[:session_id])

      expect(session.agent).to eq(agent)
    end
  end

  describe "agent resolution priority" do
    let(:hook_agent) { create(:agent, name: "armorer") }
    let(:transitioning_agent) { create(:agent, name: "grogu") }
    let(:assigned_agent) { create(:agent, name: "mando") }
    let(:assigned_task) { create(:task, title: "Build beskar armor", assigned_to_agent: assigned_agent) }

    context "when hook has an agent assigned" do
      let(:hook_with_agent) { create(:task_hook, :post, task: assigned_task, skill: skill, on_status: "review", agent: hook_agent) }

      it "reassigns the task to the hook's agent" do
        described_class.call(hook: hook_with_agent, task: assigned_task, agent: transitioning_agent)
        assigned_task.reload
        expect(assigned_task.assigned_to_agent).to eq(hook_agent)
      end

      it "creates an auto_assigned event" do
        expect {
          described_class.call(hook: hook_with_agent, task: assigned_task, agent: transitioning_agent)
        }.to change(TaskEvent, :count).by(2) # auto_assigned + hook_fired

        auto_event = TaskEvent.where(event_type: "auto_assigned").last
        expect(auto_event.summary).to include("armorer")
        expect(auto_event.summary).to include("post-hook")
      end

      it "uses the hook agent for the session, not the transitioning agent" do
        result = described_class.call(hook: hook_with_agent, task: assigned_task, agent: transitioning_agent)
        session = Session.find(result.data[:session_id])
        expect(session.agent).to eq(hook_agent)
      end

      it "does not reassign if already assigned to the hook agent" do
        assigned_task.update!(assigned_to_agent: hook_agent)
        expect {
          described_class.call(hook: hook_with_agent, task: assigned_task, agent: hook_agent)
        }.to change(TaskEvent, :count).by(1) # only hook_fired, no auto_assigned
      end
    end

    context "when hook has no agent — task assignee wins over transitioning agent" do
      let(:hook_no_agent) { create(:task_hook, :post, task: assigned_task, skill: skill, on_status: "review", agent: nil) }

      it "uses the task's assigned agent, NOT the transitioning agent" do
        result = described_class.call(hook: hook_no_agent, task: assigned_task, agent: transitioning_agent)
        session = Session.find(result.data[:session_id])

        # This is the KEY behavioral change — assignee wins over clicker
        expect(session.agent).to eq(assigned_agent)
      end

      it "does not change task assignment" do
        described_class.call(hook: hook_no_agent, task: assigned_task, agent: transitioning_agent)
        assigned_task.reload
        expect(assigned_task.assigned_to_agent).to eq(assigned_agent)
      end

      it "falls back to transitioning agent when task is unassigned" do
        unassigned_task = create(:task, title: "Unassigned task", assigned_to_agent: nil, created_by_agent: nil)
        hook = create(:task_hook, :post, task: unassigned_task, skill: skill, on_status: "review", agent: nil)

        result = described_class.call(hook: hook, task: unassigned_task, agent: transitioning_agent)
        session = Session.find(result.data[:session_id])
        expect(session.agent).to eq(transitioning_agent)
      end

      it "falls back to task creator when both assignee and transitioning agent are nil" do
        creator = create(:agent, name: "creator")
        task_with_creator = create(:task, title: "Created task", assigned_to_agent: nil, created_by_agent: creator)
        hook = create(:task_hook, :post, task: task_with_creator, skill: skill, on_status: "review", agent: nil)

        result = described_class.call(hook: hook, task: task_with_creator)
        session = Session.find(result.data[:session_id])
        expect(session.agent).to eq(creator)
      end
    end

    context "when task is reassigned between hooks (pipeline behavior)" do
      let(:hook_no_agent) { create(:task_hook, :post, task: assigned_task, skill: skill, on_status: "review", agent: nil) }

      it "picks up reassignment from a prior hook via reload" do
        new_agent = create(:agent, name: "new_owner")

        # Simulate a prior hook reassigning the task in the DB
        assigned_task.update!(assigned_to_agent: new_agent)

        # The executor should reload and pick up new_agent, not assigned_agent
        result = described_class.call(hook: hook_no_agent, task: assigned_task, agent: transitioning_agent)
        session = Session.find(result.data[:session_id])
        expect(session.agent).to eq(new_agent)
      end
    end

    context "with an unassigned task and a hook agent" do
      let(:original_agent) { create(:agent, name: "mando") }
      let(:unassigned_task) { create(:task, title: "Unassigned task", assigned_to_agent: nil, created_by_agent: original_agent) }
      let(:hook_assigns) { create(:task_hook, :post, task: unassigned_task, skill: skill, on_status: "in_progress", agent: hook_agent) }

      it "assigns the hook agent to the previously unassigned task" do
        described_class.call(hook: hook_assigns, task: unassigned_task)
        unassigned_task.reload
        expect(unassigned_task.assigned_to_agent).to eq(hook_agent)
      end
    end
  end

  describe "prompt content — slim format" do
    it "includes task description in the prompt" do
      task.update!(description: "Implement the flux capacitor")

      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("Implement the flux capacitor")
        expect(prompt).to include("### Description")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes task ID and metadata in the prompt" do
      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("##{task.id}")
        expect(prompt).to include(task.title)
        expect(prompt).to include(task.priority)
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes Work Order header with task ID" do
      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("## Work Order — Task ##{task.id}")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "does NOT inline checklist, comments, artifacts, or dependencies" do
      task.update!(
        checklist: [{ "title" => "Write tests", "checked" => false }],
        description: "Build it"
      )
      task.add_comment(author_name: "Doc Brown", body: "Great Scott!")
      task.add_artifact(type: "pr", title: "PR #42", url: "https://github.com/org/repo/pull/42", created_by: "Mando")

      blocker = create(:task, title: "Build time circuits", status: "in_progress")
      create(:task_dependency, task: task, depends_on: blocker)

      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        # These sections should NOT be in the prompt anymore
        expect(prompt).not_to include("### Checklist")
        expect(prompt).not_to include("### Comments")
        expect(prompt).not_to include("### Artifacts")
        expect(prompt).not_to include("### Dependencies")
        expect(prompt).not_to include("### Downstream Tasks")

        # Instead, the agent should be told to self-serve
        expect(prompt).to include("### Before You Start")
        expect(prompt).to include("task_manager")
        expect(prompt).to include("task_id: #{task.id}")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes self-serve instructions pointing to task_manager" do
      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("### Before You Start")
        expect(prompt).to include("task_manager")
        expect(prompt).to include("action: \"get\"")
        expect(prompt).to include("task_id: #{task.id}")
        expect(prompt).to include("checklist")
        expect(prompt).to include("comments")
        expect(prompt).to include("artifacts")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes artifact creation instructions in every prompt" do
      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("### Recording Your Work")
        expect(prompt).to include("add_artifact")
        expect(prompt).to include("**type**")
        expect(prompt).to include("`pr`, `branch`, `commit`, `file`, `url`, or `document`")
        expect(prompt).to include("next agent in the pipeline")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes skill content when skill is present" do
      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("### Skill Instructions")
        expect(prompt).to include("Do the thing")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    context "with a skillless hook (default behavior)" do
      let(:team) { agent.team || create(:team) }
      let(:skillless_hook) { create(:task_hook, team: team, skill: nil, trigger: "post", on_status: "in_progress") }

      it "uses default task instructions instead of skill content" do
        expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
          expect(prompt).to include("### Instructions")
          expect(prompt).to include("git worktree")
          expect(prompt).not_to include("### Skill Instructions")
        end

        described_class.call(hook: skillless_hook, task: task, agent: agent)
      end

      it "successfully creates a session" do
        result = described_class.call(hook: skillless_hook, task: task, agent: agent)
        expect(result).to be_success
        expect(result.data[:session_id]).to be_present
      end
    end

    context "status-specific directives" do
      let(:in_progress_hook) { create(:task_hook, :post, task: task, skill: skill, on_status: "in_progress") }
      let(:review_hook) { create(:task_hook, :post, task: task, skill: skill, on_status: "review") }
      let(:done_hook) { create(:task_hook, :post, task: task, skill: skill, on_status: "done") }

      it "includes work order directive for in_progress" do
        expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
          expect(prompt).to include("This is a work order")
          expect(prompt).to include("write the code")
          expect(prompt).to include("open a PR")
        end

        described_class.call(hook: in_progress_hook, task: task, agent: agent)
      end

      it "includes review directive for review status" do
        expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
          expect(prompt).to include("ready for review")
          expect(prompt).to include("check the PR")
          expect(prompt).to include("approve and move to `done`")
        end

        described_class.call(hook: review_hook, task: task, agent: agent)
      end

      it "includes completion directive for done status" do
        expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
          expect(prompt).to include("marked `done`")
          expect(prompt).to include("Verify completion")
        end

        described_class.call(hook: done_hook, task: task, agent: agent)
      end
    end
  end
end
