# frozen_string_literal: true

require "rails_helper"

RSpec.describe HashtagActions::Actions::Todo do
  let(:agent)   { create(:agent) }
  let(:session) { create(:session, agent: agent) }

  subject(:action) do
    described_class.new(agent: agent, session: session, payload: payload)
  end

  # ─── Happy path ───────────────────────────────────────────────

  context "with a plain payload (no priority, no assignee)" do
    let(:payload) { "Write release notes for v2" }

    it "creates a Task record" do
      expect { action.execute }.to change(Task, :count).by(1)
    end

    it "creates a MemoryEntry record" do
      expect { action.execute }.to change(MemoryEntry, :count).by(1)
    end

    it "sets the task title from the payload" do
      action.execute
      expect(Task.last.title).to eq("Write release notes for v2")
    end

    it "defaults the task to backlog / medium priority" do
      action.execute
      task = Task.last
      expect(task.status).to eq("backlog")
      expect(task.priority).to eq("medium")
    end

    it "links the task to the creating agent" do
      action.execute
      expect(Task.last.created_by_agent).to eq(agent)
    end

    it "links the task to the session" do
      action.execute
      expect(Task.last.session).to eq(session)
    end

    it "stores source metadata on the task" do
      action.execute
      expect(Task.last.metadata["source"]).to eq("hashtag_action")
      expect(Task.last.metadata["session_id"]).to eq(session.id)
    end

    it "prefixes the memory content with 'TODO:'" do
      action.execute
      expect(MemoryEntry.last.content).to eq("TODO: Write release notes for v2")
    end

    it "cross-references the task_id in the memory metadata" do
      action.execute
      task   = Task.last
      memory = MemoryEntry.last
      expect(memory.metadata["task_id"]).to eq(task.id)
    end

    it "returns a created status" do
      result = action.execute
      expect(result[:status]).to eq("created")
    end

    it "includes the task id in the response" do
      action.execute
      result = action.execute
      expect(result[:response]).to match(/Created task #\d+/)
    end

    it "includes the payload text in the response" do
      result = action.execute
      expect(result[:response]).to include("Write release notes for v2")
    end
  end

  # ─── Priority parsing ─────────────────────────────────────────

  context "with a priority bracket in the payload" do
    let(:payload) { "[high] Deploy auth flow" }

    it "extracts the priority" do
      action.execute
      expect(Task.last.priority).to eq("high")
    end

    it "strips the bracket from the title" do
      action.execute
      expect(Task.last.title).to eq("Deploy auth flow")
    end

    it "mentions the priority in the response" do
      result = action.execute
      expect(result[:response]).to include("[high]")
    end
  end

  context "with an uppercase priority bracket" do
    let(:payload) { "[URGENT] Fix production crash" }

    it "normalises priority to lowercase" do
      action.execute
      expect(Task.last.priority).to eq("urgent")
    end
  end

  context "with an unrecognised bracket" do
    let(:payload) { "[critical] Ship it" }

    it "defaults priority to medium" do
      action.execute
      expect(Task.last.priority).to eq("medium")
    end

    it "does not strip the bracket text from the title (not a recognised priority)" do
      action.execute
      expect(Task.last.title).to include("[critical]")
    end
  end

  # ─── Assignee parsing ─────────────────────────────────────────

  context "with a @mention of a known agent" do
    let(:assignee) { create(:agent, name: "Devon") }
    let(:payload)  { "[high] Deploy auth flow @#{assignee.name.downcase}" }

    it "assigns the task to that agent" do
      action.execute
      expect(Task.last.assigned_to_agent).to eq(assignee)
    end

    it "strips the @mention from the title" do
      action.execute
      expect(Task.last.title).not_to include("@#{assignee.name.downcase}")
    end

    it "mentions the assignee in the response" do
      result = action.execute
      expect(result[:response]).to include("Devon")
    end
  end

  context "with a @mention of an unknown agent" do
    let(:payload) { "Do something @nobody" }

    it "still creates the task (assignee silently ignored)" do
      expect { action.execute }.to change(Task, :count).by(1)
    end

    it "leaves assigned_to_agent nil" do
      action.execute
      expect(Task.last.assigned_to_agent).to be_nil
    end
  end

  # ─── Title-only result after stripping ───────────────────────

  context "when stripping leaves a blank title" do
    let(:payload) { "[high] @someagent" }

    it "does not create a task" do
      expect { action.execute }.not_to change(Task, :count)
    end

    it "returns no_payload status" do
      expect(action.execute[:status]).to eq("no_payload")
    end
  end

  # ─── Long payload ─────────────────────────────────────────────

  context "with a payload exactly at the truncation boundary (255 chars)" do
    let(:payload) { "x" * 255 }

    it "creates a task without error" do
      expect { action.execute }.to change(Task, :count).by(1)
    end
  end

  context "with a very long payload (> 255 chars)" do
    let(:payload) { "y" * 300 }

    it "truncates the task title to 255 characters" do
      action.execute
      expect(Task.last.title.length).to be <= 255
    end

    it "still creates the memory entry" do
      action.execute
      expect(MemoryEntry.last.content).to start_with("TODO:")
    end
  end

  # ─── Blank / nil payload ──────────────────────────────────────

  context "with a blank payload" do
    let(:payload) { "" }

    it "does not create a Task" do
      expect { action.execute }.not_to change(Task, :count)
    end

    it "does not create a MemoryEntry" do
      expect { action.execute }.not_to change(MemoryEntry, :count)
    end

    it "returns a no_payload status" do
      result = action.execute
      expect(result[:status]).to eq("no_payload")
    end

    it "returns a helpful response message" do
      result = action.execute
      expect(result[:response]).to include("#todo")
    end
  end

  context "with a nil payload" do
    let(:payload) { nil }

    it "does not create a Task" do
      expect { action.execute }.not_to change(Task, :count)
    end

    it "returns a no_payload status" do
      expect(action.execute[:status]).to eq("no_payload")
    end
  end

  # ─── Error handling ───────────────────────────────────────────

  context "when Task.new raises on save" do
    let(:payload) { "Valid payload" }

    before do
      allow_any_instance_of(Task).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(Task.new))
    end

    it "does not raise" do
      expect { action.execute }.not_to raise_error
    end

    it "returns an error status" do
      result = action.execute
      expect(result[:status]).to eq("error")
    end

    it "does not create a MemoryEntry when the Task fails" do
      expect { action.execute }.not_to change(MemoryEntry, :count)
    end
  end
end
