# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::WhatsappAdapter do
  let(:channel) { create(:channel, :whatsapp) }
  let(:adapter) { described_class.new(channel) }

  # Build a minimal Cloud API-shaped webhook payload.
  def wa_payload(msg_overrides = {})
    default_msg = {
      id: "wamid_001",
      from: "15551234567",
      type: "text",
      timestamp: "1707900000",
      text: { body: "Hello WhatsApp" }
    }
    {
      entry: [ {
        changes: [ {
          value: {
            messages: [ default_msg.merge(msg_overrides) ],
            metadata: { phone_number_id: "pn_001" },
            contacts: [ { profile: { name: "Alice" } } ]
          }
        } ]
      } ]
    }
  end

  describe "#receive" do
    it "creates an InboundMessage for a text message" do
      result = adapter.receive(wa_payload)
      expect(result).to be_success
      msg = result.data[:inbound_message]
      expect(msg).to be_a(InboundMessage)
      expect(msg.content).to eq("Hello WhatsApp")
      expect(msg.sender).to eq("15551234567")
      expect(msg.external_id).to eq("wamid_001")
    end

    it "stores contact_name and phone_number_id in metadata" do
      result = adapter.receive(wa_payload)
      meta = result.data[:inbound_message].metadata
      expect(meta["contact_name"]).to eq("Alice")
      expect(meta["phone_number_id"]).to eq("pn_001")
    end

    context "audio message" do
      let(:audio_payload) do
        wa_payload(type: "audio", audio: { file_path: "/tmp/voice.ogg" }, text: nil)
      end

      it "calls transcribe_audio and uses the transcription as content" do
        allow_any_instance_of(described_class).to receive(:transcribe_audio)
          .with("/tmp/voice.ogg")
          .and_return("Transcribed voice message")

        result = adapter.receive(audio_payload)
        expect(result).to be_success
        expect(result.data[:inbound_message].content).to eq("Transcribed voice message")
      end

      it "falls back to empty string when transcription returns nil" do
        allow_any_instance_of(described_class).to receive(:transcribe_audio).and_return(nil)

        result = adapter.receive(audio_payload)
        expect(result).to be_success
        expect(result.data[:inbound_message].content).to eq("")
      end
    end

    it "returns skipped when no message entry is present" do
      result = adapter.receive({ entry: [] })
      expect(result).to be_success
      expect(result.data[:skipped]).to be true
    end
  end

  describe "#send_message" do
    context "connector mode (default)" do
      it "POSTs to the connector /send endpoint with cleaned number and message" do
        stub_request(:post, "http://connector:3002/send")
          .with(body: hash_including("to" => "15551234567", "message" => "Hello!"))
          .to_return(status: 200, body: { "status" => "sent" }.to_json)

        result = adapter.send_message(to: "15551234567", content: "Hello!")
        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
      end

      it "strips the WhatsApp JID suffix (@s.whatsapp.net) from the recipient" do
        stub_request(:post, "http://connector:3002/send")
          .with(body: hash_including("to" => "15551234567"))
          .to_return(status: 200, body: { "status" => "sent" }.to_json)

        result = adapter.send_message(to: "15551234567@s.whatsapp.net", content: "JID test")
        expect(result).to be_success
      end

      it "returns failure when the connector reports an error status" do
        stub_request(:post, "http://connector:3002/send")
          .to_return(status: 200, body: { "status" => "error", "error" => "rate limited" }.to_json)

        result = adapter.send_message(to: "15551234567", content: "fail")
        expect(result).not_to be_success
        expect(result.error).to include("rate limited")
      end

      it "returns failure when the connector is unreachable" do
        stub_request(:post, "http://connector:3002/send").to_raise(Errno::ECONNREFUSED)

        result = adapter.send_message(to: "15551234567", content: "no connector")
        expect(result).not_to be_success
        expect(result.error).to include("connector not running at http://connector:3002")
      end
    end

    context "Cloud API mode" do
      let(:access_token) { "EAAtest_cloud_token" }
      let(:phone_number_id) { "pn_cloud_001" }

      before do
        channel.update!(config: channel.config.merge(
          "mode" => "cloud_api",
          "phone_number_id" => phone_number_id
        ))
        create(:vault_entry, namespace: "channel_credentials", key: "whatsapp_access_token", value: access_token)
      end

      it "POSTs to the Graph API with Bearer auth and logs an OutboundMessage" do
        stub_request(:post, "https://graph.facebook.com/v21.0/#{phone_number_id}/messages")
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 200, body: { "messages" => [ { "id" => "wamid_cloud_001" } ] }.to_json)

        result = adapter.send_message(to: "15551234567", content: "Cloud message")
        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        expect(result.data[:outbound_message].metadata["wamid"]).to eq("wamid_cloud_001")
      end

      it "sends a properly structured Cloud API payload" do
        stub_request(:post, "https://graph.facebook.com/v21.0/#{phone_number_id}/messages")
          .with(body: /"messaging_product":"whatsapp"/)
          .to_return(status: 200, body: { "messages" => [ { "id" => "wamid_002" } ] }.to_json)

        result = adapter.send_message(to: "+15551234567", content: "Body test")
        expect(result).to be_success
      end

      it "returns failure when the Graph API returns an error" do
        stub_request(:post, "https://graph.facebook.com/v21.0/#{phone_number_id}/messages")
          .to_return(status: 200, body: { "error" => { "message" => "Invalid token" } }.to_json)

        result = adapter.send_message(to: "15551234567", content: "bad token")
        expect(result).not_to be_success
        expect(result.error).to include("Invalid token")
      end

      it "returns failure when access_token or phone_number_id is missing" do
        VaultEntry.where(namespace: "channel_credentials", key: "whatsapp_access_token").destroy_all

        result = adapter.send_message(to: "15551234567", content: "no creds")
        expect(result).not_to be_success
        expect(result.error).to include("credentials not configured")
      end
    end
  end

  describe "#verify_webhook" do
    context "connector mode (default)" do
      it "always returns true — connector bridge is internal, no signature needed" do
        result = adapter.verify_webhook(double("request"))
        expect(result).to be true
      end
    end

    context "Cloud API mode" do
      let(:hmac_secret) { "vault_hmac_secret_value" }

      before do
        channel.update!(config: channel.config.merge("mode" => "cloud_api"))
        create(:vault_entry, namespace: "channel_webhooks", key: "whatsapp_secret", value: hmac_secret)
      end

      it "accepts a request with a valid HMAC-SHA256 signature" do
        body = '{"object":"whatsapp_business_account"}'
        sig  = OpenSSL::HMAC.hexdigest("SHA256", hmac_secret, body)

        request = double("request",
          headers: { "X-Hub-Signature-256" => "sha256=#{sig}" },
          raw_post: body
        )

        expect(adapter.verify_webhook(request)).to be true
      end

      it "rejects a request with an invalid signature" do
        request = double("request",
          headers: { "X-Hub-Signature-256" => "sha256=badhash" },
          raw_post: '{"object":"whatsapp_business_account"}'
        )

        expect(adapter.verify_webhook(request)).to be false
      end

      it "returns false when the X-Hub-Signature-256 header is absent" do
        request = double("request", headers: {})

        expect(adapter.verify_webhook(request)).to be false
      end

      it "returns true when no vault secret is configured (verification optional)" do
        VaultEntry.where(namespace: "channel_webhooks", key: "whatsapp_secret").destroy_all
        result = adapter.verify_webhook(double("request"))
        expect(result).to be true
      end

      # Previously broken: gate checked app_secret (config) but HMAC used vault secret.
      # Now both use the vault secret — test the two previously-broken combinations.
      it "skips verification when config has app_secret but vault entry is absent" do
        VaultEntry.where(namespace: "channel_webhooks", key: "whatsapp_secret").destroy_all
        channel.update!(config: channel.config.merge("app_secret" => "irrelevant"))
        result = adapter.verify_webhook(double("request"))
        expect(result).to be true
      end

      it "verifies signature when vault secret exists even without app_secret in config" do
        body = '{"object":"whatsapp_business_account"}'
        sig  = OpenSSL::HMAC.hexdigest("SHA256", hmac_secret, body)
        request = double("request",
          headers: { "X-Hub-Signature-256" => "sha256=#{sig}" },
          raw_post: body
        )
        # config has no app_secret — vault secret alone must trigger verification
        expect(channel.config.key?("app_secret")).to be false
        expect(adapter.verify_webhook(request)).to be true
      end
    end
  end
end
