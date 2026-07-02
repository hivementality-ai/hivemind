# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhook endpoints", type: :request do
  describe "as an owner" do
    let(:user) { create(:user, :owner) }
    before { sign_in user }

    it "lists endpoints" do
      create(:webhook_endpoint)
      get webhook_endpoints_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("example.com")
    end

    it "creates an endpoint and shows the secret once in the flash" do
      post webhook_endpoints_path, params: {
        webhook_endpoint: { url: "https://example.com/hook", event_types: [ "task.completed" ], enabled: "1" }
      }

      expect(response).to redirect_to(webhook_endpoints_path)
      ep = WebhookEndpoint.last
      expect(ep).to be_present
      expect(ep.url).to eq("https://example.com/hook")
      expect(ep.event_types).to eq([ "task.completed" ])

      # Secret is in the redirect flash, not re-rendered on the next page
      follow_redirect!
      expect(response.body).to include(ep.secret)

      # Secret does NOT appear on the index page on a fresh visit
      get webhook_endpoints_path
      expect(response.body).not_to include(ep.secret)
    end

    it "does not allow setting secret via params" do
      post webhook_endpoints_path, params: {
        webhook_endpoint: { url: "https://example.com/hook", event_types: [ "task.completed" ], secret: "injected" }
      }
      expect(WebhookEndpoint.last&.secret).not_to eq("injected")
    end

    it "re-renders on invalid URL" do
      post webhook_endpoints_path, params: {
        webhook_endpoint: { url: "http://not-https.com", event_types: [ "task.completed" ] }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "updates an endpoint" do
      ep = create(:webhook_endpoint, url: "https://example.com/old")
      patch webhook_endpoint_path(ep), params: {
        webhook_endpoint: { url: "https://example.com/new", event_types: [ "approval.resolved" ], enabled: "1" }
      }
      expect(response).to redirect_to(webhook_endpoints_path)
      expect(ep.reload.url).to eq("https://example.com/new")
      expect(ep.event_types).to eq([ "approval.resolved" ])
    end

    it "destroys an endpoint" do
      ep = create(:webhook_endpoint)
      expect { delete webhook_endpoint_path(ep) }.to change(WebhookEndpoint, :count).by(-1)
      expect(response).to redirect_to(webhook_endpoints_path)
    end
  end

  describe "as a viewer" do
    before { sign_in create(:user, :viewer) }

    it "is denied access" do
      get webhook_endpoints_path
      expect(response).to redirect_to(root_path)
    end
  end
end
