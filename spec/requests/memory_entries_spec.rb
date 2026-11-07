# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MemoryEntries", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, :owner) }
  let(:viewer) { create(:user, :viewer) }
  let(:agent)  { create(:agent, name: "Ada") }
  let(:base)   { "/agents/#{agent.slug}/memories" }
  let!(:memory) { create(:memory_entry, agent: agent, memory_type: "semantic", content: "Remember the project uses Rails") }

  before { allow(Memory::Embedding).to receive(:generate_query).and_return(nil) }

  describe "GET /agents/:agent_slug/memories" do
    context "as a signed-in user" do
      before { sign_in owner }

      it "is titled in plain words" do
        get base
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("What Ada remembers about you")
      end

      it "lists the agent's memories" do
        get base
        expect(response.body).to include("Remember the project uses Rails")
      end

      it "groups memories by kind with plain headings" do
        create(:memory_entry, agent: agent, memory_type: "preference", category: "user_preference", content: "Likes short answers")
        create(:memory_entry, agent: agent, memory_type: "semantic", category: "project_context", content: "Launch is in March")

        get base

        body = response.body
        expect(body).to include("Things you like")
        expect(body).to include("Your projects")
        expect(body).to include("Facts")
        expect(body.index("Likes short answers")).to be > body.index("Things you like")
        expect(body.index("Launch is in March")).to be > body.index("Your projects")
      end

      it "lists newest first within a group" do
        create(:memory_entry, agent: agent, memory_type: "semantic", content: "Older fact", created_at: 3.days.ago)
        create(:memory_entry, agent: agent, memory_type: "semantic", content: "Newer fact", created_at: 1.hour.ago)

        get base

        expect(response.body.index("Newer fact")).to be < response.body.index("Older fact")
      end

      it "filters via q param (keyword fallback)" do
        create(:memory_entry, agent: agent, memory_type: "semantic", content: "Unrelated fact about cats")

        get base, params: { q: "Rails" }

        expect(response.body).to include("Remember the project uses Rails")
        expect(response.body).not_to include("Unrelated fact about cats")
      end

      it "does not show raw conversation logs or transcripts" do
        create(:memory_entry, agent: agent, memory_type: "episodic", content: "User: hi\nAssistant: hello there")
        create(:memory_entry, agent: agent, memory_type: "semantic", source_type: "TranscriptArchive", source_id: 1,
                              content: "Archived transcript body")

        get base

        expect(response.body).not_to include("hello there")
        expect(response.body).not_to include("Archived transcript body")
        expect(response.body).to include("Remember the project uses Rails")
      end

      it "keeps transcripts out of search results too" do
        create(:memory_entry, agent: agent, memory_type: "episodic", content: "Rails chat log line")

        get base, params: { q: "Rails" }

        expect(response.body).not_to include("Rails chat log line")
      end

      it "hides forgotten memories from the list and offers a restore" do
        forgotten = create(:memory_entry, agent: agent, memory_type: "semantic", content: "Forgotten thing")
        forgotten.forget!

        get base

        expect(response.body).to include("Recently forgotten")
        expect(response.body).to include("#{base}/#{forgotten.id}/restore")
      end

      it "only shows this agent's memories" do
        other = create(:agent)
        create(:memory_entry, agent: other, memory_type: "semantic", content: "Secret of the other agent")

        get base

        expect(response.body).not_to include("Secret of the other agent")
      end

      it "returns 404 for an unknown agent" do
        get "/agents/nope/memories"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "as a viewer" do
      before { sign_in viewer }

      it "is accessible but offers no edit controls" do
        get base
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Forget everything about")
      end
    end
  end

  describe "navigation" do
    before { sign_in owner }

    it "links the agent page and the sidebar to the memory page" do
      get agent_path(agent)
      expect(response.body).to include(%(href="#{base}"))

      get agents_path
      expect(response.body).to include("What I remember")
    end

    it "still shows the page and its sidebar link in Simple mode" do
      SimpleMode.enabled = true

      get agents_path
      expect(response.body).to include("What I remember")

      get base
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("What Ada remembers about you")
    end
  end

  describe "PATCH /agents/:agent_slug/memories/:id" do
    context "as an owner" do
      before { sign_in owner }

      it "edits the text" do
        patch "#{base}/#{memory.id}", params: { memory_entry: { content: "The project uses Hanami" } }

        expect(response).to redirect_to(base)
        expect(memory.reload.content).to eq("The project uses Hanami")
      end

      it "re-embeds when the memory was embedded" do
        memory.update_columns(embedding: Array.new(768, 0.1))

        expect do
          patch "#{base}/#{memory.id}", params: { memory_entry: { content: "New wording" } }
        end.to have_enqueued_job(MemoryEmbeddingJob).with(memory.id)

        expect(memory.reload.embedding).to be_nil
      end

      it "does not re-embed when the text is unchanged" do
        memory.update_columns(embedding: Array.new(768, 0.1))

        expect do
          patch "#{base}/#{memory.id}", params: { memory_entry: { content: memory.content } }
        end.not_to have_enqueued_job(MemoryEmbeddingJob)

        expect(memory.reload.embedding).to be_present
      end

      it "rejects blank text" do
        patch "#{base}/#{memory.id}", params: { memory_entry: { content: "  " } }

        expect(memory.reload.content).to eq("Remember the project uses Rails")
        expect(flash[:alert]).to be_present
      end
    end

    context "as a viewer" do
      before { sign_in viewer }

      it "is denied" do
        patch "#{base}/#{memory.id}", params: { memory_entry: { content: "Hacked" } }
        expect(response).to redirect_to(root_path)
        expect(memory.reload.content).to eq("Remember the project uses Rails")
      end
    end
  end

  describe "DELETE /agents/:agent_slug/memories/:id" do
    context "as an owner" do
      before { sign_in owner }

      it "forgets the memory softly and redirects" do
        delete "#{base}/#{memory.id}"

        expect(response).to redirect_to(base)
        expect(MemoryEntry.exists?(memory.id)).to be(true)
        expect(memory.reload.status).to eq("archived")
        expect(memory.metadata).to have_key("forgotten_at")
      end

      it "removes an already forgotten memory for good" do
        memory.forget!

        delete "#{base}/#{memory.id}"

        expect(MemoryEntry.exists?(memory.id)).to be(false)
      end
    end

    context "as a viewer" do
      before { sign_in viewer }

      it "is denied" do
        delete "#{base}/#{memory.id}"
        expect(response).to redirect_to(root_path)
        expect(memory.reload.status).to eq("active")
      end
    end
  end

  describe "POST /agents/:agent_slug/memories/:id/restore" do
    before { sign_in owner }

    it "brings a forgotten memory back" do
      memory.forget!

      post "#{base}/#{memory.id}/restore"

      expect(response).to redirect_to(base)
      expect(memory.reload.status).to eq("active")
      expect(memory.metadata).not_to have_key("forgotten_at")
    end
  end

  describe "PATCH /agents/:agent_slug/memories/:id/pin" do
    before { sign_in owner }

    it "pins and unpins" do
      patch "#{base}/#{memory.id}/pin", params: { pinned: "true" }
      expect(memory.reload).to be_pinned

      patch "#{base}/#{memory.id}/pin", params: { pinned: "false" }
      expect(memory.reload).not_to be_pinned
    end

    it "lists pinned memories first" do
      create(:memory_entry, agent: agent, memory_type: "semantic", content: "Newest fact")
      memory.update!(pinned: true, created_at: 5.days.ago)

      get base

      expect(response.body.index("Remember the project uses Rails")).to be < response.body.index("Newest fact")
    end
  end

  describe "forgetting everything about a topic" do
    before { sign_in owner }

    let!(:cat1) { create(:memory_entry, agent: agent, memory_type: "semantic", content: "Has a cat named Miso") }
    let!(:cat2) { create(:memory_entry, agent: agent, memory_type: "preference", category: "user_preference", content: "Hates CAT videos") }
    let!(:pinned_cat) { create(:memory_entry, agent: agent, memory_type: "semantic", pinned: true, content: "Cat allergy noted") }

    it "shows exactly what will go before deleting anything" do
      get "#{base}/forget", params: { topic: "cat" }

      expect(response.body).to include("Has a cat named Miso")
      expect(response.body).to include("Hates CAT videos")
      expect(response.body).not_to include("Remember the project uses Rails")
      expect(response.body).to include("1 pinned")
      expect(MemoryEntry.where(agent: agent).count).to eq(4)
    end

    it "deletes only the confirmed, unpinned matches for good" do
      delete "#{base}/forget", params: { topic: "cat", ids: [ cat1.id ] }

      expect(MemoryEntry.exists?(cat1.id)).to be(false)
      expect(MemoryEntry.exists?(cat2.id)).to be(true)
      expect(MemoryEntry.exists?(pinned_cat.id)).to be(true)
      expect(MemoryEntry.exists?(memory.id)).to be(true)
      expect(response).to redirect_to(base)
    end

    it "keeps a pinned memory even when its id is sent" do
      delete "#{base}/forget", params: { topic: "cat", ids: [ cat1.id, pinned_cat.id ] }

      expect(MemoryEntry.exists?(pinned_cat.id)).to be(true)
    end

    it "never deletes another agent's memory even when its id is sent" do
      other = create(:memory_entry, agent: create(:agent), memory_type: "semantic", content: "cat of another agent")

      delete "#{base}/forget", params: { topic: "cat", ids: [ cat1.id, other.id ] }

      expect(MemoryEntry.exists?(other.id)).to be(true)
      expect(MemoryEntry.exists?(cat1.id)).to be(false)
    end

    it "does nothing for a blank topic" do
      get "#{base}/forget", params: { topic: " " }
      expect(response).to redirect_to(base)
    end

    it "is denied for a viewer" do
      sign_in viewer
      delete "#{base}/forget", params: { topic: "cat", ids: [ cat1.id ] }
      expect(response).to redirect_to(root_path)
      expect(MemoryEntry.exists?(cat1.id)).to be(true)
    end
  end

  describe "agent scoping" do
    before { sign_in owner }

    let(:other_agent) { create(:agent) }
    let!(:foreign) { create(:memory_entry, agent: other_agent, memory_type: "semantic", content: "Foreign memory") }

    it "cannot edit another agent's memory through this agent" do
      patch "#{base}/#{foreign.id}", params: { memory_entry: { content: "changed" } }

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.content).to eq("Foreign memory")
    end

    it "cannot forget another agent's memory through this agent" do
      delete "#{base}/#{foreign.id}"

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.status).to eq("active")
    end

    it "cannot restore another agent's memory through this agent" do
      foreign.forget!

      post "#{base}/#{foreign.id}/restore"

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.status).to eq("archived")
    end

    it "cannot pin another agent's memory through this agent" do
      patch "#{base}/#{foreign.id}/pin", params: { pinned: "true" }

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload).not_to be_pinned
    end
  end

  describe "sidebar landing" do
    before { sign_in owner }

    it "goes straight to the only agent's page" do
      get "/memories"
      expect(response).to redirect_to(base)
    end

    it "sends the user to the agent list when there are several agents" do
      create(:agent)

      get "/memories"

      expect(response).to redirect_to(agents_path)
    end
  end

  describe "pinned memories survive supersession" do
    it "keeps a pinned memory when something newer replaces it" do
      replacement = create(:memory_entry, agent: agent, content: "New")
      memory.update!(pinned: true)

      memory.supersede_with!(replacement)

      expect(memory.reload.status).to eq("active")
    end
  end
end
