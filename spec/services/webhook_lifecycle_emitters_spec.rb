# frozen_string_literal: true

require "rails_helper"

RSpec.describe "webhook lifecycle emitters" do
  let(:agent) { create(:agent) }

  describe "session.started" do
    it "enqueues WebhookDeliveryJob for a subscribed endpoint when a session is created" do
      endpoint = create(:webhook_endpoint, event_types: [ "session.started" ])
      expect {
        create(:session, agent: agent)
      }.to have_enqueued_job(WebhookDeliveryJob)
        .with(endpoint.id, "session.started", hash_including(agent_id: agent.id))
    end

    it "does not enqueue for an endpoint subscribed to a different event" do
      agent # force creation before the endpoint exists so agent.created doesn't match
      create(:webhook_endpoint, event_types: [ "agent.created" ])
      expect {
        create(:session, agent: agent)
      }.not_to have_enqueued_job(WebhookDeliveryJob)
    end
  end

  describe "session.completed" do
    it "routes to subscribed endpoints" do
      endpoint = create(:webhook_endpoint, event_types: [ "session.completed" ])
      session = create(:session, agent: agent)
      expect {
        WebhookEmitter.emit(
          "session.completed",
          { session_id: session.id, agent_id: agent.id, title: session.title, completed_at: Time.current.iso8601 },
          agent: agent
        )
      }.to have_enqueued_job(WebhookDeliveryJob)
        .with(endpoint.id, "session.completed", hash_including(session_id: session.id))
    end
  end

  describe "agent.created" do
    it "enqueues WebhookDeliveryJob for a subscribed endpoint when an agent is created" do
      endpoint = create(:webhook_endpoint, event_types: [ "agent.created" ])
      expect {
        create(:agent, name: "New Agent #{SecureRandom.hex(4)}")
      }.to have_enqueued_job(WebhookDeliveryJob)
        .with(endpoint.id, "agent.created", hash_including(name: a_string_starting_with("New Agent")))
    end

    it "does not enqueue for a disabled endpoint" do
      create(:webhook_endpoint, :disabled, event_types: [ "agent.created" ])
      expect {
        create(:agent)
      }.not_to have_enqueued_job(WebhookDeliveryJob)
    end
  end

  describe "agent.deleted" do
    it "enqueues WebhookDeliveryJob for a subscribed endpoint when an agent is destroyed" do
      endpoint = create(:webhook_endpoint, event_types: [ "agent.deleted" ])
      target = create(:agent)
      expect {
        target.destroy
      }.to have_enqueued_job(WebhookDeliveryJob)
        .with(endpoint.id, "agent.deleted", hash_including(agent_id: target.id))
    end
  end

  describe "heartbeat.completed" do
    it "enqueues WebhookDeliveryJob for a subscribed endpoint when a heartbeat run is created" do
      endpoint = create(:webhook_endpoint, event_types: [ "heartbeat.completed" ])
      expect {
        create(:heartbeat_run, agent: agent)
      }.to have_enqueued_job(WebhookDeliveryJob)
        .with(endpoint.id, "heartbeat.completed", hash_including(agent_id: agent.id, status: "ok"))
    end

    it "fires for error-status heartbeat runs too" do
      endpoint = create(:webhook_endpoint, event_types: [ "heartbeat.completed" ])
      expect {
        create(:heartbeat_run, :error, agent: agent)
      }.to have_enqueued_job(WebhookDeliveryJob)
        .with(endpoint.id, "heartbeat.completed", hash_including(status: "error"))
    end
  end
end
