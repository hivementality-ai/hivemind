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

  describe "budget fields on the edit form" do
    it "points to the Budgets page instead of offering a limit field in cents" do
      get "/agents/#{agent.slug}/edit"

      expect(response.body).not_to include("agent[daily_budget_limit]")
      expect(response.body).not_to include("(cents)")
      expect(response.body).to include(%(href="#{budgets_path}"))
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

  describe "provider selection" do
    let!(:omlx) { create(:provider_config, :openai_compatible, name: "oMLX", base_url: "http://192.168.1.6:8000/v1") }
    let!(:router) { create(:provider_config, :openai_compatible, name: "OpenRouter", base_url: "https://openrouter.ai/api/v1") }

    it "saves the chosen provider_config_id and keeps model_provider in step" do
      patch "/agents/#{agent.slug}", params: { agent: { provider_config_id: router.id, llm_model: "m" } }

      agent.reload
      expect(agent.provider_config_id).to eq(router.id)
      expect(agent.model_provider).to eq("openai_compatible")
    end

    it "lists each provider by name on the edit form" do
      get "/agents/#{agent.slug}/edit"

      expect(response.body).to include(%(<option value="#{omlx.id}">oMLX</option>))
      expect(response.body).to include(%(<option value="#{router.id}">OpenRouter</option>))
    end

    it "lists models from the selected provider config" do
      omlx.update!(model_definitions: [ { "id" => "qwen-local" } ])
      router.update!(model_definitions: [ { "id" => "gpt-routed" } ])

      get "/api/v1/providers/models", params: { provider_config_id: router.id }

      expect(JSON.parse(response.body)["models"]).to eq([ { "id" => "gpt-routed", "name" => "gpt-routed" } ])
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
