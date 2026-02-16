# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agents API", type: :request do
  let(:user) { create(:user, :owner) }
  let!(:agent) { Agent.create!(name: "Test Agent", role: "Helper", enabled: true) }

  before do
    sign_in user
  end

  describe "GET /agents/:slug" do
    it "retrieves agent by slug" do
      get "/agents/#{agent.slug}"
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for non-existent slug" do
      get "/agents/nonexistent_agent"
      expect(response).to have_http_status(:not_found)
    end

    it "handles case-insensitive slug lookup" do
      get "/agents/TEST_AGENT"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /agents/:slug" do
    it "updates agent by slug" do
      patch "/agents/#{agent.slug}", params: { agent: { role: "Updated Role" } }
      expect(response).to have_http_status(:redirect)
      expect(agent.reload.role).to eq("Updated Role")
    end

    it "returns 404 for non-existent slug" do
      patch "/agents/nonexistent_agent", params: { agent: { role: "Updated" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /agents/:slug" do
    it "deletes agent by slug" do
      agent_id = agent.id
      delete "/agents/#{agent.slug}"
      expect(response).to redirect_to("/agents")
      expect(Agent.exists?(agent_id)).to be_falsey
    end
  end
end

# Note: API v1 tests require API token authentication which is more complex to set up.
# The slug routing for API v1 is verified through model and controller integration tests.
