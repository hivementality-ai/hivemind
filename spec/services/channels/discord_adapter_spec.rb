# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::DiscordAdapter do
  let(:channel) { create(:channel, :discord) }
  let(:adapter) { described_class.new(channel) }
  let(:bot_token) { "Bot_token_abc123" }

  before do
    create(:vault_entry, namespace: "channel_credentials", key: "discord_bot_token", value: bot_token)
  end

  describe "#receive" do
    context "PING (type 1)" do
      it "returns pong immediately without creating an InboundMessage" do
        result = adapter.receive({ "type" => 1 })
        expect(result).to be_success
        expect(result.data[:pong]).to be true
      end
    end

    context "APPLICATION_COMMAND (type 2)" do
      let(:payload) do
        {
          "type" => 2,
          "id" => "inter_123",
          "channel_id" => "C123",
          "guild_id" => "G123",
          "token" => "itoken_xyz",
          "data" => { "name" => "help", "options" => [ { "name" => "topic", "value" => "rspec" } ] },
          "member" => { "user" => { "id" => "U456" } }
        }
      end

      it "creates an InboundMessage with reconstructed slash-command content" do
        result = adapter.receive(payload)
        expect(result).to be_success
        msg = result.data[:inbound_message]
        expect(msg).to be_a(InboundMessage)
        expect(msg.content).to eq("/help topic:rspec")
        expect(msg.sender).to eq("U456")
        expect(result.data[:interaction]).to be true
      end

      it "stores channel_id, guild_id, and interaction token in metadata" do
        result = adapter.receive(payload)
        meta = result.data[:inbound_message].metadata
        expect(meta["channel_id"]).to eq("C123")
        expect(meta["guild_id"]).to eq("G123")
        expect(meta["token"]).to eq("itoken_xyz")
        expect(meta["interaction_type"]).to eq(2)
      end
    end

    context "MESSAGE_CREATE (direct payload)" do
      let(:payload) do
        {
          "id" => "msg_001",
          "content" => "Hello Discord",
          "channel_id" => "C123",
          "guild_id" => "G123",
          "author" => { "id" => "U999", "bot" => false }
        }
      end

      it "creates an InboundMessage with sender and content" do
        result = adapter.receive(payload)
        expect(result).to be_success
        msg = result.data[:inbound_message]
        expect(msg).to be_a(InboundMessage)
        expect(msg.content).to eq("Hello Discord")
        expect(msg.sender).to eq("U999")
        expect(msg.external_id).to eq("msg_001")
      end

      it "stores channel and guild in metadata" do
        result = adapter.receive(payload)
        meta = result.data[:inbound_message].metadata
        expect(meta["channel_id"]).to eq("C123")
        expect(meta["guild_id"]).to eq("G123")
      end

      it "skips bot messages" do
        payload["author"]["bot"] = true
        result = adapter.receive(payload)
        expect(result).to be_success
        expect(result.data[:skipped]).to be true
      end
    end

    context "gateway MESSAGE_CREATE envelope (t: 'MESSAGE_CREATE', d: …)" do
      it "extracts the message from the :d key" do
        payload = {
          "t" => "MESSAGE_CREATE",
          "d" => {
            "id" => "msg_002",
            "content" => "Gateway hello",
            "channel_id" => "C456",
            "guild_id" => "G456",
            "author" => { "id" => "U888" }
          }
        }
        result = adapter.receive(payload)
        expect(result).to be_success
        msg = result.data[:inbound_message]
        expect(msg.content).to eq("Gateway hello")
        expect(msg.sender).to eq("U888")
      end
    end

    context "thread message" do
      it "extracts thread_id from the :thread key" do
        payload = {
          "id" => "msg_003",
          "content" => "Thread reply",
          "channel_id" => "T999",
          "guild_id" => "G123",
          "author" => { "id" => "U111" },
          "thread" => { "id" => "T999" }
        }
        result = adapter.receive(payload)
        expect(result).to be_success
        expect(result.data[:inbound_message].metadata["thread_id"]).to eq("T999")
      end
    end

    context "unrecognised payload" do
      it "returns skipped for payloads with no content or MESSAGE_CREATE marker" do
        result = adapter.receive({})
        expect(result).to be_success
        expect(result.data[:skipped]).to be true
      end
    end
  end

  describe "#send_message" do
    context "plain text" do
      it "POSTs to the channel, authenticates with Bot token, and logs an OutboundMessage" do
        stub_request(:post, "https://discord.com/api/v10/channels/C123/messages")
          .with(headers: { "Authorization" => "Bot #{bot_token}" })
          .to_return(status: 200, body: { "id" => "out_001", "channel_id" => "C123" }.to_json)

        result = adapter.send_message(to: "C123", content: "Hello!")
        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        expect(result.data[:response]["id"]).to eq("out_001")
      end
    end

    context "with thread_id" do
      it "sends to the thread channel rather than the parent channel" do
        stub_request(:post, "https://discord.com/api/v10/channels/T999/messages")
          .with(headers: { "Authorization" => "Bot #{bot_token}" })
          .to_return(status: 200, body: { "id" => "thread_msg" }.to_json)

        result = adapter.send_message(to: "C123", content: "Thread reply", thread_id: "T999")
        expect(result).to be_success
      end
    end

    context "with reply_to_message_id" do
      it "includes message_reference in the request body" do
        stub_request(:post, "https://discord.com/api/v10/channels/C123/messages")
          .with(body: /message_reference/)
          .to_return(status: 200, body: { "id" => "reply_msg" }.to_json)

        result = adapter.send_message(to: "C123", content: "Reply", reply_to_message_id: "orig_123")
        expect(result).to be_success
      end
    end

    context "API error" do
      it "returns a failure containing the HTTP status" do
        stub_request(:post, "https://discord.com/api/v10/channels/C123/messages")
          .to_return(status: 403, body: { "message" => "Missing Permissions" }.to_json)

        result = adapter.send_message(to: "C123", content: "Fail")
        expect(result).not_to be_success
        expect(result.error).to include("403")
      end
    end

    context "no bot token configured" do
      before do
        VaultEntry.where(namespace: "channel_credentials", key: "discord_bot_token").destroy_all
      end

      it "returns failure without making an HTTP request" do
        result = adapter.send_message(to: "C123", content: "no token")
        expect(result).not_to be_success
        expect(result.error).to include("Bot token not configured")
      end
    end

    context "file upload (local file)" do
      let(:temp_file) do
        file = Tempfile.new([ "discord_test", ".png" ], encoding: "ascii-8bit")
        file.write("\x89PNG\r\n\x1a\n" + "png content")
        file.rewind
        file
      end

      after { temp_file.close && temp_file.unlink }

      it "uploads via multipart and logs an OutboundMessage" do
        stub_request(:post, "https://discord.com/api/v10/channels/C123/messages")
          .to_return(status: 200, body: { "id" => "file_msg_001" }.to_json)

        result = adapter.send_message(to: "C123", content: "Here is a file", file_path: temp_file.path)
        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
      end

      it "returns failure for non-existent file paths" do
        result = adapter.send_message(to: "C123", content: "missing", file_path: "/no/such/file.png")
        expect(result).not_to be_success
        expect(result.error).to include("Invalid file path")
      end
    end

    context "file upload (remote URL)" do
      it "downloads, uploads, and records the filename in OutboundMessage metadata" do
        stub_request(:get, "https://example.com/photo.png")
          .to_return(status: 200, body: "png bytes")
        stub_request(:post, "https://discord.com/api/v10/channels/C123/messages")
          .to_return(status: 200, body: { "id" => "url_msg_001" }.to_json)

        result = adapter.send_message(to: "C123", content: "Remote", url: "https://example.com/photo.png")
        expect(result).to be_success
        expect(result.data[:outbound_message].metadata["file_name"]).to eq("photo.png")
      end

      it "returns failure on download error" do
        stub_request(:get, "https://example.com/missing.png").to_return(status: 404)

        result = adapter.send_message(to: "C123", content: "bad", url: "https://example.com/missing.png")
        expect(result).not_to be_success
        expect(result.error).to include("download")
      end
    end
  end

  describe "#send_typing" do
    it "POSTs to the typing endpoint and succeeds on 204" do
      stub_request(:post, "https://discord.com/api/v10/channels/C123/typing")
        .with(headers: { "Authorization" => "Bot #{bot_token}" })
        .to_return(status: 204, body: "")

      result = adapter.send_typing(channel_id: "C123")
      expect(result).to be_success
    end

    it "returns failure on API error" do
      stub_request(:post, "https://discord.com/api/v10/channels/C123/typing")
        .to_return(status: 403, body: "Forbidden")

      result = adapter.send_typing(channel_id: "C123")
      expect(result).not_to be_success
      expect(result.error).to include("Typing failed")
    end
  end

  describe "#react" do
    it "PUTs the URL-encoded emoji on the message and succeeds on 204" do
      # 👍 encodes to %F0%9F%91%8D
      stub_request(:put, "https://discord.com/api/v10/channels/C123/messages/msg_001/reactions/%F0%9F%91%8D/@me")
        .with(headers: { "Authorization" => "Bot #{bot_token}" })
        .to_return(status: 204, body: "")

      result = adapter.react(channel_id: "C123", message_id: "msg_001", emoji: "👍")
      expect(result).to be_success
    end

    it "returns failure when the API rejects the reaction" do
      stub_request(:put, /reactions/).to_return(status: 400, body: { "message" => "Unknown Emoji" }.to_json)

      result = adapter.react(channel_id: "C123", message_id: "msg_001", emoji: "??")
      expect(result).not_to be_success
      expect(result.error).to include("Reaction failed")
    end
  end

  describe "#respond_to_interaction" do
    it "POSTs a type-4 callback with the ephemeral flag (64) set" do
      stub_request(:post, "https://discord.com/api/v10/interactions/iid_123/itoken_abc/callback")
        .with(body: /"type":4/)
        .to_return(status: 204, body: "")

      result = adapter.respond_to_interaction(
        interaction_id: "iid_123",
        interaction_token: "itoken_abc",
        content: "Done!",
        ephemeral: true
      )
      expect(result).to be_success
      expect(result.data[:ephemeral]).to be true

      expect(WebMock).to have_requested(:post, "https://discord.com/api/v10/interactions/iid_123/itoken_abc/callback")
        .with(body: /"flags":64/)
    end

    it "omits the ephemeral flag when ephemeral: false" do
      stub_request(:post, "https://discord.com/api/v10/interactions/iid_123/itoken_abc/callback")
        .to_return(status: 200, body: "")

      result = adapter.respond_to_interaction(
        interaction_id: "iid_123",
        interaction_token: "itoken_abc",
        content: "Public reply",
        ephemeral: false
      )
      expect(result).to be_success

      expect(WebMock).not_to have_requested(:post, "https://discord.com/api/v10/interactions/iid_123/itoken_abc/callback")
        .with(body: /"flags":64/)
    end
  end

  describe "#verify_webhook" do
    context "without Ed25519 headers (gateway/internal forwarding)" do
      it "trusts Docker internal IPs (172.x.x.x)" do
        request = double("request", headers: {}, remote_ip: "172.18.0.5")
        expect(adapter.verify_webhook(request)).to be true
      end

      it "trusts localhost" do
        request = double("request", headers: {}, remote_ip: "127.0.0.1")
        expect(adapter.verify_webhook(request)).to be true
      end

      it "rejects external IPs with no headers" do
        request = double("request", headers: {}, remote_ip: "8.8.8.8")
        expect(adapter.verify_webhook(request)).to be false
      end
    end

    context "with Ed25519 signature headers" do
      let(:signing_key) { Ed25519::SigningKey.generate }
      let(:verify_key_hex) { signing_key.verify_key.to_bytes.unpack1("H*") }

      before do
        channel.update!(config: channel.config.merge("discord_public_key" => verify_key_hex))
      end

      it "accepts a validly-signed request" do
        timestamp = Time.now.to_i.to_s
        body = '{"type":2}'
        signature_hex = signing_key.sign(timestamp + body).unpack1("H*")

        request = double("request",
          headers: {
            "X-Signature-Ed25519" => signature_hex,
            "X-Signature-Timestamp" => timestamp
          },
          raw_post: body
        )

        expect(adapter.verify_webhook(request)).to be true
      end

      it "rejects a tampered signature" do
        # Ed25519 signatures are 64 bytes; provide 128 hex chars that are valid length but wrong value
        request = double("request",
          headers: {
            "X-Signature-Ed25519" => "ab" * 64,
            "X-Signature-Timestamp" => Time.now.to_i.to_s
          },
          raw_post: '{"type":2}'
        )

        expect(adapter.verify_webhook(request)).to be false
      end

      it "returns false when no public key is configured" do
        channel.update!(config: {})

        request = double("request",
          headers: {
            "X-Signature-Ed25519" => "ab" * 64,
            "X-Signature-Timestamp" => Time.now.to_i.to_s
          },
          raw_post: '{"type":2}'
        )

        expect(adapter.verify_webhook(request)).to be false
      end
    end
  end

  describe "private helpers" do
    describe "#build_multipart_body" do
      it "includes boundary markers, payload_json part, and file part" do
        body = adapter.send(:build_multipart_body,
          boundary: "testboundary",
          message_content: "Here you go",
          filename: "report.pdf",
          file_content: "%PDF-1.4 content"
        )

        expect(body).to include("testboundary")
        expect(body).to include("payload_json")
        expect(body).to include("Here you go")
        expect(body).to include("report.pdf")
        expect(body).to include("%PDF-1.4 content")
        expect(body).to include('files[0]')
        expect(body).to include("application/pdf")
      end

      it "falls back to 'File upload' when message_content is blank" do
        body = adapter.send(:build_multipart_body,
          boundary: "b",
          message_content: nil,
          filename: "f.txt",
          file_content: "data"
        )
        expect(body).to include("File upload")
      end
    end

    describe "#determine_content_type" do
      it "maps known extensions to MIME types" do
        {
          "image.png"   => "image/png",
          "photo.jpg"   => "image/jpeg",
          "anim.gif"    => "image/gif",
          "doc.pdf"     => "application/pdf",
          "note.txt"    => "text/plain",
          "clip.mp3"    => "audio/mpeg",
          "video.mp4"   => "video/mp4",
          "arc.zip"     => "application/zip",
          "data.json"   => "application/json",
          "unknown.xyz" => "application/octet-stream"
        }.each do |filename, expected|
          expect(adapter.send(:determine_content_type, filename)).to eq(expected)
        end
      end
    end
  end
end
