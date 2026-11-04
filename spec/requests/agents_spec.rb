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

  describe "budget bar on the agent page" do
    before { agent.update!(model_provider: "anthropic", llm_model: "claude-sonnet-4-5") }

    it "shows spend against the daily AgentBudget" do
      create(:agent_budget, agent: agent, period: "daily", limit_cents: 500)
      UsageRecord.create!(agent: agent, llm_model: "claude-sonnet-4-5", provider: "anthropic", input_tokens: 1, output_tokens: 1, cost_cents: 125)

      get "/agents/#{agent.slug}"

      expect(response.body).to include("agent-budget-bar", "25.0% of $5.00 limit")
    end

    it "hides the bar when there is no daily budget" do
      agent.update!(daily_budget_limit: 10)

      get "/agents/#{agent.slug}"

      expect(response.body).not_to include("agent-budget-bar")
      expect(response.body).not_to include("limit</div>")
    end
  end

  describe "connector checklist on the edit form" do
    it "checks every connector for an agent with no exclusions and unchecks an excluded one" do
      shown = create(:connector, name: "Shown API")
      hidden = create(:connector, name: "Hidden API")
      create(:agent_connector_exclusion, agent: agent, connector: hidden)

      get "/agents/#{agent.slug}/edit"

      expect(response.body).to include("Unchecking a connector hides it from this agent")
      expect(response.body).to match(/id="agent_visible_connector_ids_#{shown.id}"[^>]*checked/)
      expect(response.body).not_to match(/id="agent_visible_connector_ids_#{hidden.id}"[^>]*checked/)
    end
  end

  describe "PATCH /agents/:slug" do
    it "updates agent by slug" do
      patch "/agents/#{agent.slug}", params: { agent: { role: "Updated Role" } }
      expect(response).to have_http_status(:redirect)
      expect(agent.reload.role).to eq("Updated Role")
    end

    it "excludes the connectors left unchecked and keeps the checked ones" do
      kept = create(:connector)
      dropped = create(:connector)

      patch "/agents/#{agent.slug}", params: { agent: { visible_connector_ids: [ "", kept.id.to_s ] } }

      expect(agent.reload.excluded_connectors).to contain_exactly(dropped)
      expect(agent.visible_connectors).to contain_exactly(kept)
    end

    it "does not hide a disabled connector that is enabled after the form was saved" do
      shown = create(:connector)
      later = create(:connector, enabled: false)

      patch "/agents/#{agent.slug}", params: { agent: { visible_connector_ids: [ "", shown.id.to_s ] } }
      later.update!(enabled: true)

      expect(agent.reload.visible_connectors).to include(later)
    end

    it "restores a connector that is checked again" do
      connector = create(:connector)
      create(:agent_connector_exclusion, agent: agent, connector: connector)

      patch "/agents/#{agent.slug}", params: { agent: { visible_connector_ids: [ "", connector.id.to_s ] } }

      expect(agent.reload.excluded_connectors).to be_empty
    end

    it "leaves exclusions alone when the form does not send the checklist" do
      connector = create(:connector)
      create(:agent_connector_exclusion, agent: agent, connector: connector)

      patch "/agents/#{agent.slug}", params: { agent: { role: "Updated Role" } }

      expect(agent.reload.excluded_connectors).to contain_exactly(connector)
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

    it "tells the user what to check when an Ollama provider shows no models" do
      create(:provider_config, :ollama, name: "Mac Studio")

      get "/agents/#{agent.slug}/edit"

      expect(response.body).to include("No models listed for an Ollama provider? Make sure Ollama is running")
    end

    it "leaves the Ollama hint off when no Ollama provider is enabled" do
      get "/agents/#{agent.slug}/edit"

      expect(response.body).not_to include("Make sure Ollama is running")
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
