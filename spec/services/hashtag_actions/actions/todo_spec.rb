# frozen_string_literal: true

require "rails_helper"

RSpec.describe HashtagActions::Actions::Todo do
  let(:agent)   { create(:agent) }
  let(:session) { create(:session, agent: agent) }

  subject(:action) do
    described_class.new(agent: agent, session: session, payload: payload)
  end

  # ─── Happy path ───────────────────────────────────────────────

  context "with a valid payload" do
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

    it "records the session_id in memory metadata" do
      action.execute
      expect(MemoryEntry.last.metadata["session_id"]).to eq(session.id)
    end

    it "returns a created status" do
      result = action.execute
      expect(result[:status]).to eq("created")
    end

    it "returns a response mentioning the task id" do
      action.execute
      result = action.execute
      task_id = Task.order(created_at: :desc).second.id
      # The first execute creates task N, second creates N+1; just check format
      expect(result[:response]).to match(/Created task #\d+/)
    end

    it "includes the payload text in the response" do
      result = action.execute
      expect(result[:response]).to include("Write release notes for v2")
    end
  end

  # ─── Edge cases ───────────────────────────────────────────────

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

    it "still creates the memory entry with the full content prefix" do
      action.execute
      expect(MemoryEntry.last.content).to start_with("TODO:")
    end
  end

  # ─── Sad path: blank payload ──────────────────────────────────

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

  context "when Task.create! raises" do
    let(:payload) { "Valid payload" }

    before do
      allow(Task).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Task.new))
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
