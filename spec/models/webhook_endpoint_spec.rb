# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoint, type: :model do
  describe "validations" do
    it "is valid with an https url and event types" do
      expect(build(:webhook_endpoint)).to be_valid
    end

    it "rejects non-https urls" do
      endpoint = build(:webhook_endpoint, url: "http://example.com/hook")
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:url]).to be_present
    end

    it "rejects malformed urls" do
      endpoint = build(:webhook_endpoint, url: "not a url")
      expect(endpoint).not_to be_valid
    end

    it "requires event_types to be an array of strings" do
      expect(build(:webhook_endpoint, event_types: "task.completed")).not_to be_valid
      expect(build(:webhook_endpoint, event_types: [ 1, 2 ])).not_to be_valid
      expect(build(:webhook_endpoint, event_types: [ "task.completed" ])).to be_valid
    end

    it "auto-generates a signing secret on create" do
      endpoint = create(:webhook_endpoint)
      expect(endpoint.secret).to be_present
      expect(endpoint.secret.length).to be >= 32
    end
  end

  describe "scoping" do
    let(:agent) { create(:agent) }
    let(:team) { create(:team) }
    let(:other_agent) { create(:agent) }

    let!(:global)  { create(:webhook_endpoint) }
    let!(:scoped)  { create(:webhook_endpoint, agent: agent) }
    let!(:teamed)  { create(:webhook_endpoint, team: team) }
    let!(:other)   { create(:webhook_endpoint, agent: other_agent) }

    it "returns global endpoints plus the given agent and team" do
      result = described_class.in_scope(agent: agent, team: team)
      expect(result).to include(global, scoped, teamed)
      expect(result).not_to include(other)
    end

    it "returns only global endpoints when no scope given" do
      result = described_class.in_scope
      expect(result).to contain_exactly(global)
    end

    it "filters by subscribed event" do
      a = create(:webhook_endpoint, event_types: [ "task.completed", "approval.resolved" ])
      b = create(:webhook_endpoint, event_types: [ "approval.resolved" ])
      expect(described_class.subscribed_to("task.completed")).to include(a)
      expect(described_class.subscribed_to("task.completed")).not_to include(b)
    end
  end

  describe "delivery bookkeeping" do
    let(:endpoint) { create(:webhook_endpoint) }

    it "resets failure tracking on success" do
      endpoint.update!(failure_count: 3)
      endpoint.record_success!(200)
      expect(endpoint.failure_count).to eq(0)
      expect(endpoint.last_status).to eq(200)
      expect(endpoint.last_delivered_at).to be_present
    end

    it "increments failure_count on failure" do
      expect { endpoint.record_failure!(500) }.to change { endpoint.reload.failure_count }.from(0).to(1)
      expect(endpoint.last_status).to eq(500)
    end

    it "stays enabled below the failure ceiling" do
      (described_class::MAX_FAILURES - 1).times { endpoint.record_failure! }
      expect(endpoint.reload).to be_enabled
    end

    it "auto-disables after MAX_FAILURES consecutive failures" do
      described_class::MAX_FAILURES.times { endpoint.record_failure! }
      expect(endpoint.reload).not_to be_enabled
      expect(endpoint.failure_count).to eq(described_class::MAX_FAILURES)
    end
  end
end
