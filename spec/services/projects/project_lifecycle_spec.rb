# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project Lifecycle", type: :model do
  let(:team) { create(:team) }
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent, :with_team, team: team) }

  describe "happy path: create → active → milestones → review → approve → complete" do
    let!(:project) do
      create(:project, team: team, user: user, lead_agent: agent, status: "active", started_at: Time.current)
    end

    let!(:milestone_1) do
      create(:project_milestone,
        project: project, agent: agent, title: "Research",
        position: 0, requires_approval: false)
    end

    let!(:milestone_2) do
      create(:project_milestone,
        project: project, agent: agent, title: "Implementation",
        position: 1, depends_on: [ milestone_1.id ], requires_approval: true)
    end

    let!(:milestone_3) do
      create(:project_milestone,
        project: project, agent: agent, title: "Final Report",
        position: 2, depends_on: [ milestone_2.id ], requires_approval: true)
    end

    it "tracks progress percentage correctly" do
      expect(project.progress_percentage).to eq(0)

      milestone_1.update!(status: "completed", completed_at: Time.current)
      expect(project.reload.progress_percentage).to eq(33)

      milestone_2.update!(status: "completed", completed_at: Time.current)
      expect(project.reload.progress_percentage).to eq(67)

      milestone_3.update!(status: "completed", completed_at: Time.current)
      expect(project.reload.progress_percentage).to eq(100)
    end

    it "respects dependency chains in ready_to_start?" do
      expect(milestone_1.ready_to_start?).to be true
      expect(milestone_2.ready_to_start?).to be false
      expect(milestone_3.ready_to_start?).to be false

      milestone_1.update!(status: "completed", completed_at: Time.current)
      expect(milestone_2.reload.ready_to_start?).to be true
      expect(milestone_3.reload.ready_to_start?).to be false

      milestone_2.update!(status: "completed", completed_at: Time.current)
      expect(milestone_3.reload.ready_to_start?).to be true
    end

    it "auto-approves milestones that don't require approval" do
      expect(milestone_1.auto_approve?).to be true
      expect(milestone_2.auto_approve?).to be false
    end

    it "detects blocked state when milestones need review" do
      expect(project.blocked?).to be false

      milestone_1.update!(status: "needs_review")
      expect(project.reload.blocked?).to be true
    end
  end

  describe "dependencies_met? edge cases" do
    let(:project) { create(:project, team: team, user: user) }

    it "returns true when depends_on is empty" do
      milestone = create(:project_milestone, project: project, depends_on: [])
      expect(milestone.dependencies_met?).to be true
    end

    it "returns false when dependency is not completed" do
      dep = create(:project_milestone, project: project, status: "in_progress")
      milestone = create(:project_milestone, project: project, depends_on: [ dep.id ])
      expect(milestone.dependencies_met?).to be false
    end

    it "returns false when dependency ID does not exist" do
      milestone = create(:project_milestone, project: project, depends_on: [ 999_999 ])
      expect(milestone.dependencies_met?).to be false
    end

    it "validates dependencies are in the same project" do
      other_project = create(:project, team: team, user: user)
      other_milestone = create(:project_milestone, project: other_project)

      milestone = build(:project_milestone, project: project, depends_on: [ other_milestone.id ])
      expect(milestone).not_to be_valid
      expect(milestone.errors[:depends_on]).to include("contains milestones from a different project")
    end
  end

  describe Project do
    it "has valid factory" do
      project = build(:project, team: team, user: user)
      expect(project).to be_valid
    end

    it "validates status inclusion" do
      project = build(:project, team: team, user: user, status: "invalid")
      expect(project).not_to be_valid
    end

    it "validates priority inclusion" do
      project = build(:project, team: team, user: user, priority: "invalid")
      expect(project).not_to be_valid
    end

    it "requires title" do
      project = build(:project, team: team, user: user, title: nil)
      expect(project).not_to be_valid
    end

    it "generates workspace_path with id" do
      project = create(:project, team: team, user: user, title: "My Cool Project")
      expect(project.workspace_path).to eq("/workspace/projects/my_cool_project_#{project.id}")
    end

    it "returns notification_pref defaults" do
      project = build(:project, team: team, user: user)
      expect(project.digest_mode).to eq("realtime")
      expect(project.approval_reminder_hours).to eq(4)
      expect(project.approval_max_reminders).to eq(3)
      expect(project.approval_escalation_hours).to eq(24)
    end

    it "reads custom notification_prefs" do
      project = build(:project, team: team, user: user, notification_prefs: {
        "digest_mode" => "daily",
        "approval_reminder_hours" => 12
      })
      expect(project.digest_mode).to eq("daily")
      expect(project.approval_reminder_hours).to eq(12)
    end
  end

  describe ProjectEvent do
    it "has valid factory" do
      project = create(:project, team: team, user: user)
      event = build(:project_event, project: project)
      expect(event).to be_valid
    end

    it "requires event_type and summary" do
      project = create(:project, team: team, user: user)
      expect(build(:project_event, project: project, event_type: nil)).not_to be_valid
      expect(build(:project_event, project: project, summary: nil)).not_to be_valid
    end
  end
end

RSpec.describe Projects::Coordinator, type: :service do
  let(:team) { create(:team) }
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent, :with_team, team: team) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(ChatStreamJob).to receive(:perform_later)
  end

  describe "#call" do
    it "starts the first unblocked milestone" do
      project = create(:project, :active, team: team, user: user)
      milestone = create(:project_milestone, project: project, agent: agent, status: "pending")

      described_class.call

      expect(milestone.reload.status).to eq("in_progress")
      expect(ChatStreamJob).to have_received(:perform_later)
    end

    it "does not start milestones when one is already in_progress" do
      project = create(:project, :active, team: team, user: user)
      create(:project_milestone, project: project, agent: agent, status: "in_progress", started_at: Time.current,
        session: create(:session, agent: agent, last_activity_at: Time.current))
      pending_milestone = create(:project_milestone, project: project, agent: agent, status: "pending", position: 1)

      described_class.call

      expect(pending_milestone.reload.status).to eq("pending")
    end

    it "marks project completed when all milestones are done" do
      project = create(:project, :active, team: team, user: user)
      create(:project_milestone, project: project, agent: agent, status: "completed", completed_at: Time.current)

      described_class.call

      expect(project.reload.status).to eq("completed")
      expect(project.completed_at).to be_present
    end

    it "marks project blocked when milestone needs review" do
      project = create(:project, :active, team: team, user: user)
      create(:project_milestone, project: project, agent: agent, status: "needs_review")

      described_class.call

      expect(project.reload.status).to eq("blocked")
    end

    it "unblocks project when approval is cleared" do
      project = create(:project, :blocked, team: team, user: user)
      create(:project_milestone, project: project, agent: agent, status: "completed", completed_at: Time.current)
      create(:project_milestone, project: project, agent: agent, status: "pending", position: 1)

      described_class.call

      expect(project.reload.status).to eq("active")
    end

    it "does not duplicate completed event" do
      project = create(:project, :active, team: team, user: user)
      create(:project_milestone, project: project, agent: agent, status: "completed", completed_at: Time.current)

      described_class.call
      expect(project.reload.status).to eq("completed")

      expect { described_class.call }.not_to change { ProjectEvent.where(event_type: "project_completed").count }
    end

    it "handles errors on individual projects gracefully" do
      project = create(:project, :active, team: team, user: user)
      allow_any_instance_of(Projects::ApprovalReminder).to receive(:call).and_raise(StandardError, "boom")

      expect { described_class.call }.not_to raise_error
    end
  end
end

RSpec.describe Projects::StallDetector, type: :service do
  let(:team) { create(:team) }
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent, :with_team, team: team) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(ChatStreamJob).to receive(:perform_later)
  end

  it "detects stalled milestones and triggers resume" do
    project = create(:project, :active, team: team, user: user)
    stale_session = create(:session, agent: agent, last_activity_at: 2.hours.ago)
    milestone = create(:project_milestone,
      project: project, agent: agent, status: "in_progress",
      session: stale_session, started_at: 2.hours.ago)

    described_class.call(project: project)

    # Should have created a new session via MilestoneRunner resume
    expect(milestone.reload.session_id).not_to eq(stale_session.id)
    expect(ChatStreamJob).to have_received(:perform_later)
  end

  it "does not resume active milestones" do
    project = create(:project, :active, team: team, user: user)
    active_session = create(:session, agent: agent, last_activity_at: 5.minutes.ago)
    milestone = create(:project_milestone,
      project: project, agent: agent, status: "in_progress",
      session: active_session, started_at: 10.minutes.ago)

    described_class.call(project: project)

    expect(milestone.reload.session_id).to eq(active_session.id)
    expect(ChatStreamJob).not_to have_received(:perform_later)
  end
end

RSpec.describe Projects::EventLogger, type: :service do
  let(:team) { create(:team) }
  let(:user) { create(:user, :owner) }

  before { allow(ActionCable.server).to receive(:broadcast) }

  it "creates a ProjectEvent and broadcasts" do
    project = create(:project, team: team, user: user)

    expect {
      described_class.call(project: project, event_type: "test", summary: "Test event")
    }.to change(ProjectEvent, :count).by(1)

    expect(ActionCable.server).to have_received(:broadcast).with(
      "project_#{project.id}",
      hash_including(type: "project_event", event_type: "test")
    )
  end
end

RSpec.describe Projects::CheckpointWriter, type: :service do
  let(:team) { create(:team) }
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent, :with_team, team: team) }

  before { allow(ActionCable.server).to receive(:broadcast) }

  it "saves checkpoint data to the milestone" do
    project = create(:project, team: team, user: user)
    session = create(:session, agent: agent, transcript: [])
    milestone = create(:project_milestone, project: project, agent: agent, session: session)

    described_class.call(
      milestone: milestone,
      agent: agent,
      session: session,
      completed_steps: [ "Step 1 done", "Step 2 done" ],
      pending_steps: [ "Step 3" ],
      notes: "Making progress"
    )

    checkpoint = milestone.reload.checkpoint
    expect(checkpoint["completed_steps"]).to eq([ "Step 1 done", "Step 2 done" ])
    expect(checkpoint["pending_steps"]).to eq([ "Step 3" ])
    expect(checkpoint["context_notes"]).to eq("Making progress")
    expect(checkpoint["session_id"]).to eq(session.id)
  end
end

RSpec.describe Projects::ContextBuilder, type: :service do
  let(:team) { create(:team) }
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent, :with_team, team: team) }

  it "builds initial context with project and milestone info" do
    project = create(:project, team: team, user: user, title: "Test Project", description: "Build something")
    milestone = create(:project_milestone, project: project, agent: agent,
      title: "Phase 1", description: "Research phase", acceptance_criteria: "Find 5 sources")

    context = described_class.call(milestone: milestone, resume: false)

    expect(context).to include("Test Project")
    expect(context).to include("Phase 1")
    expect(context).to include("Find 5 sources")
    expect(context).to include("project_update")
  end

  it "builds resume context with checkpoint data" do
    project = create(:project, team: team, user: user, title: "Test Project")
    session = create(:session, agent: agent)
    milestone = create(:project_milestone, project: project, agent: agent, session: session,
      title: "Phase 1", description: "Research",
      checkpoint: {
        "completed_steps" => [ "Found 3 sources" ],
        "pending_steps" => [ "Find 2 more sources" ],
        "context_notes" => "User wants academic sources only"
      })

    context = described_class.call(milestone: milestone, resume: true)

    expect(context).to include("RESUMING MILESTONE")
    expect(context).to include("Found 3 sources")
    expect(context).to include("Find 2 more sources")
    expect(context).to include("academic sources only")
    expect(context).to include("Do NOT repeat completed work")
  end

  it "includes rejection feedback when retrying" do
    project = create(:project, team: team, user: user)
    milestone = create(:project_milestone, project: project, agent: agent,
      review_notes: "Too verbose, be concise", retry_count: 1)

    context = described_class.call(milestone: milestone, resume: false)

    expect(context).to include("Too verbose, be concise")
    expect(context).to include("Revision 1")
  end
end
