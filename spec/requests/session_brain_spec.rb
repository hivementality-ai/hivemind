# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Session brain override", type: :request do
  let(:user) { create(:user, :owner) }
  let(:session) { create(:session) }
  let(:config) { create(:provider_config, :anthropic) }

  before { sign_in user }

  describe "PATCH /sessions/:id/brain" do
    it "saves the provider and model on the session" do
      patch brain_session_path(session), params: { provider_config_id: config.id, llm_model: "claude-x" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(session.reload).to have_attributes(provider_config_id: config.id, llm_model: "claude-x")
    end

    it "clears the override when blank" do
      session.update!(provider_config: config, llm_model: "claude-x")

      patch brain_session_path(session), params: { provider_config_id: nil, llm_model: nil }, as: :json

      expect(response).to have_http_status(:ok)
      expect(session.reload).to have_attributes(provider_config_id: nil, llm_model: nil)
    end

    it "rejects a model without an enabled provider" do
      disabled = create(:provider_config, :openai, enabled: false)

      patch brain_session_path(session), params: { provider_config_id: disabled.id, llm_model: "gpt-x" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(session.reload.llm_model).to be_nil
    end
  end
end
