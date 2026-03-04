# frozen_string_literal: true

require "rails_helper"

RSpec.describe NetworkEgress::PolicyCheck do
  let(:agent) { create(:agent) }

  describe ".call" do
    context "with no egress policy" do
      it "allows all requests" do
        result = described_class.call(agent: agent, url: "https://example.com")
        expect(result.allowed?).to be true
      end
    end

    context "with disabled mode" do
      before do
        agent.update!(egress_policy: { "mode" => "disabled", "rules" => [] })
      end

      it "allows all requests" do
        result = described_class.call(agent: agent, url: "https://example.com")
        expect(result.allowed?).to be true
      end
    end

    context "with allowlist mode" do
      before do
        agent.update!(egress_policy: {
          "mode" => "allowlist",
          "rules" => [
            { "pattern" => "api.github.com" },
            { "pattern" => "*.example.com" }
          ],
          "log_blocked" => true
        })
      end

      it "allows exact match" do
        result = described_class.call(agent: agent, url: "https://api.github.com/repos")
        expect(result.allowed?).to be true
      end

      it "allows glob match" do
        result = described_class.call(agent: agent, url: "https://sub.example.com/page")
        expect(result.allowed?).to be true
      end

      it "allows glob root domain match" do
        result = described_class.call(agent: agent, url: "https://example.com/page")
        expect(result.allowed?).to be true
      end

      it "blocks non-matching host" do
        result = described_class.call(agent: agent, url: "https://evil.com/steal")
        expect(result.allowed?).to be false
        expect(result.reason).to include("not in allowlist")
      end

      it "logs blocked requests to AuditLog" do
        expect {
          described_class.call(agent: agent, url: "https://evil.com/steal")
        }.to change(AuditLog, :count).by(1)

        log = AuditLog.last
        expect(log.action).to eq("network_egress.blocked")
        expect(log.actor_type).to eq("agent")
        expect(log.actor_id).to eq(agent.id.to_s)
        expect(log.metadata["host"]).to eq("evil.com")
      end
    end

    context "with blocklist mode" do
      before do
        agent.update!(egress_policy: {
          "mode" => "blocklist",
          "rules" => [
            { "pattern" => "*.evil.com" },
            { "pattern" => "malware.net" }
          ],
          "log_blocked" => true
        })
      end

      it "blocks matching glob pattern" do
        result = described_class.call(agent: agent, url: "https://sub.evil.com/page")
        expect(result.allowed?).to be false
        expect(result.reason).to include("matches blocklist")
      end

      it "blocks exact match" do
        result = described_class.call(agent: agent, url: "https://malware.net/bad")
        expect(result.allowed?).to be false
      end

      it "allows non-matching host" do
        result = described_class.call(agent: agent, url: "https://github.com/good")
        expect(result.allowed?).to be true
      end

      it "logs blocked requests" do
        expect {
          described_class.call(agent: agent, url: "https://malware.net/x")
        }.to change(AuditLog, :count).by(1)
      end
    end

    context "with CIDR notation" do
      before do
        agent.update!(egress_policy: {
          "mode" => "blocklist",
          "rules" => [{ "pattern" => "10.0.0.0/8" }],
          "log_blocked" => false
        })
      end

      it "blocks IP within CIDR range" do
        result = described_class.call(agent: agent, url: "http://10.1.2.3/internal")
        expect(result.allowed?).to be false
      end

      it "allows IP outside CIDR range" do
        result = described_class.call(agent: agent, url: "http://192.168.1.1/external")
        expect(result.allowed?).to be true
      end

      it "does not log when log_blocked is false" do
        expect {
          described_class.call(agent: agent, url: "http://10.1.2.3/internal")
        }.not_to change(AuditLog, :count)
      end
    end

    context "with port matching" do
      before do
        agent.update!(egress_policy: {
          "mode" => "allowlist",
          "rules" => [
            { "pattern" => "api.example.com", "port" => 443 }
          ],
          "log_blocked" => false
        })
      end

      it "allows matching host and port" do
        result = described_class.call(agent: agent, url: "https://api.example.com/data")
        expect(result.allowed?).to be true
      end

      it "blocks matching host with wrong port" do
        result = described_class.call(agent: agent, url: "http://api.example.com/data")
        expect(result.allowed?).to be false
      end
    end

    context "with invalid URL" do
      before do
        agent.update!(egress_policy: { "mode" => "allowlist", "rules" => [] })
      end

      it "denies invalid URLs" do
        result = described_class.call(agent: agent, url: "not a url")
        expect(result.allowed?).to be false
        expect(result.reason).to include("invalid URL")
      end
    end
  end
end
