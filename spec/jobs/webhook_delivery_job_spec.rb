# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookDeliveryJob, type: :job do
  let(:endpoint) { create(:webhook_endpoint, url: "https://example.com/hook") }

  it "POSTs a signed JSON payload with a valid HMAC signature header" do
    captured = nil
    stub_request(:post, endpoint.url)
      .with { |req| captured = req; true }
      .to_return(status: 200)

    described_class.perform_now(endpoint.id, "task.completed", { "task_id" => 7 })

    expect(captured).not_to be_nil
    expect(captured.headers["Content-Type"]).to eq("application/json")
    expect(captured.headers["X-Hivemind-Event"]).to eq("task.completed")

    payload = JSON.parse(captured.body)
    expect(payload["event"]).to eq("task.completed")
    expect(payload["data"]).to eq({ "task_id" => 7 })
    expect(payload["timestamp"]).to be_present

    # Signature must match HMAC-SHA256 of the raw body using the endpoint secret.
    expected = OpenSSL::HMAC.hexdigest("sha256", endpoint.secret, captured.body)
    expect(captured.headers["X-Hivemind-Signature"]).to eq(expected)
  end

  it "records a successful delivery and clears failure tracking" do
    endpoint.update!(failure_count: 2)
    stub_request(:post, endpoint.url).to_return(status: 204)

    described_class.perform_now(endpoint.id, "task.completed", {})

    endpoint.reload
    expect(endpoint.last_status).to eq(204)
    expect(endpoint.failure_count).to eq(0)
    expect(endpoint.last_delivered_at).to be_present
  end

  it "increments failure_count on a non-2xx response" do
    stub_request(:post, endpoint.url).to_return(status: 500)

    expect do
      described_class.perform_now(endpoint.id, "task.completed", {})
    end.to change { endpoint.reload.failure_count }.from(0).to(1)
    expect(endpoint.last_status).to eq(500)
  end

  it "increments failure_count on a network error" do
    stub_request(:post, endpoint.url).to_timeout

    expect do
      described_class.perform_now(endpoint.id, "task.completed", {})
    end.to change { endpoint.reload.failure_count }.from(0).to(1)
  end

  it "disables the endpoint after MAX_FAILURES consecutive failures" do
    stub_request(:post, endpoint.url).to_return(status: 500)

    WebhookEndpoint::MAX_FAILURES.times do
      described_class.perform_now(endpoint.id, "task.completed", {})
    end

    expect(endpoint.reload).not_to be_enabled
  end

  it "does nothing for a disabled endpoint" do
    endpoint.update!(enabled: false)
    described_class.perform_now(endpoint.id, "task.completed", {})
    expect(a_request(:post, endpoint.url)).not_to have_been_made
  end
end
