# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEmitter do
  let(:agent) { create(:agent) }

  it "enqueues one delivery job per enabled, subscribed, in-scope endpoint" do
    match_global = create(:webhook_endpoint, event_types: [ "task.completed" ])
    match_agent  = create(:webhook_endpoint, event_types: [ "task.completed" ], agent: agent)

    # Excluded: disabled, wrong event, out of scope
    create(:webhook_endpoint, :disabled, event_types: [ "task.completed" ])
    create(:webhook_endpoint, event_types: [ "approval.resolved" ])
    create(:webhook_endpoint, event_types: [ "task.completed" ], agent: create(:agent))

    expect do
      WebhookEmitter.emit("task.completed", { task_id: 1 }, agent: agent)
    end.to have_enqueued_job(WebhookDeliveryJob).twice

    expect(WebhookDeliveryJob).to have_been_enqueued.with(match_global.id, "task.completed", { task_id: 1 })
    expect(WebhookDeliveryJob).to have_been_enqueued.with(match_agent.id, "task.completed", { task_id: 1 })
  end

  it "enqueues nothing when no endpoint subscribes to the event" do
    create(:webhook_endpoint, event_types: [ "approval.resolved" ])
    expect do
      WebhookEmitter.emit("task.completed", {}, agent: agent)
    end.not_to have_enqueued_job(WebhookDeliveryJob)
  end
end
