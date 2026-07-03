# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MemoryEntries", type: :request do
  let(:owner) { create(:user, :owner) }
  let(:viewer) { create(:user, :viewer) }
  let(:agent)  { create(:agent) }
  let!(:memory) { create(:memory_entry, agent: agent, content: "Remember the project uses Rails") }

  describe "GET /agents/:agent_slug/memories" do
    context "as a signed-in user" do
      before { sign_in owner }

      it "lists the agent's memories" do
        get "/agents/#{agent.slug}/memories"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Remember the project uses Rails")
      end

      it "filters via q param (keyword fallback)" do
        create(:memory_entry, agent: agent, content: "Unrelated fact about cats")

        # stub embedding so keyword fallback is used
        allow(Memory::Embedding).to receive(:generate_query).and_return(nil)

        get "/agents/#{agent.slug}/memories", params: { q: "Rails" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Remember the project uses Rails")
        expect(response.body).not_to include("Unrelated fact about cats")
      end
    end

    context "as a viewer" do
      before { sign_in viewer }

      it "is accessible" do
        get "/agents/#{agent.slug}/memories"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "DELETE /agents/:agent_slug/memories/:id" do
    context "as an owner" do
      before { sign_in owner }

      it "destroys the memory and redirects" do
        delete "/agents/#{agent.slug}/memories/#{memory.id}"
        expect(response).to redirect_to(agent_memory_entries_path(agent))
        expect(MemoryEntry.exists?(memory.id)).to be_falsey
      end
    end

    context "as a viewer" do
      before { sign_in viewer }

      it "is denied" do
        delete "/agents/#{agent.slug}/memories/#{memory.id}"
        expect(response).to redirect_to(root_path)
        expect(MemoryEntry.exists?(memory.id)).to be_truthy
      end
    end
  end
end
