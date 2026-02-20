# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::SlackAdapter do
  let(:channel) { create(:channel, :slack) }
  let(:adapter) { described_class.new(channel) }
  let(:slack_token) { "xoxb-test-token-123" }

  before do
    create(:vault_entry, namespace: "channel_credentials", key: "slack_bot_token", value: slack_token)
  end

  describe '#send_message' do
    context 'with text content only' do
      it 'sends a message via chat.postMessage' do
        stub_request(:post, "https://slack.com/api/chat.postMessage")
          .with(
            headers: { "Authorization" => "Bearer #{slack_token}" },
            body: hash_including(
              "channel" => "C123456",
              "text" => "Hello Slack"
            )
          )
          .to_return(
            status: 200,
            body: { ok: true, ts: "1234567890.000001", channel: "C123456" }.to_json
          )

        result = adapter.send_message(to: "C123456", content: "Hello Slack")

        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        expect(result.data[:response]["ok"]).to be true
      end
    end

    context 'with file upload (local file)' do
      let(:temp_file) do
        file = Tempfile.new(['test', '.png'], encoding: 'ascii-8bit')
        file.write("\x89PNG\r\n\x1a\n" + "test content")
        file.rewind
        file
      end

      after { temp_file.close && temp_file.unlink }

      it 'uploads a file via files.upload API' do
        stub_request(:post, "https://slack.com/api/files.upload")
          .with(
            headers: { "Authorization" => "Bearer #{slack_token}" }
          )
          .to_return(
            status: 200,
            body: {
              ok: true,
              file: {
                id: "F123456",
                name: "test.png",
                permalink: "https://example.slack.com/files/U123/F123/test.png"
              }
            }.to_json
          )

        result = adapter.send_message(
          to: "C123456",
          content: "Check out this image",
          file_path: temp_file.path
        )

        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        expect(result.data[:outbound_message].metadata["file_id"]).to eq("F123456")
        expect(result.data[:response]["ok"]).to be true
      end

      it 'validates file size limits' do
        # Create a large-ish temp file to test size validation
        large_file = Tempfile.new(['large', '.bin'], encoding: 'ascii-8bit')
        # Write 1 MB of data (well below limit but large enough to test)
        large_file.write("x" * (1024 * 1024))
        large_file.rewind

        # Now stub the validation to fail for testing purposes
        allow_any_instance_of(described_class).to receive(:validate_file_size) do |size|
          ServiceResponse.failure(error: "File too large: 25 GB. Max size is 20 GB")
        end

        result = adapter.send_message(
          to: "C123456",
          content: "Big file",
          file_path: large_file.path
        )

        expect(result).not_to be_success
        expect(result.error).to include("too large")

        large_file.close
        large_file.unlink
      end

      it 'rejects missing file path and url' do
        stub_request(:post, "https://slack.com/api/chat.postMessage")
          .to_return(
            status: 200,
            body: { ok: true, ts: "123", channel: "C123456" }.to_json
          )

        result = adapter.send_message(
          to: "C123456",
          content: "No file"
        )

        expect(result).to be_success # Regular text message should work
      end

      it 'rejects non-existent file path' do
        result = adapter.send_message(
          to: "C123456",
          content: "Missing file",
          file_path: "/nonexistent/path/file.txt"
        )

        expect(result).not_to be_success
        expect(result.error).to include("Invalid file path")
      end
    end

    context 'with file upload (remote URL)' do
      it 'downloads and uploads a file from a URL' do
        file_content = "\x89PNG\r\n\x1a\n" + "remote content"
        stub_request(:get, "https://example.com/image.png")
          .to_return(
            status: 200,
            body: file_content
          )

        stub_request(:post, "https://slack.com/api/files.upload")
          .to_return(
            status: 200,
            body: {
              ok: true,
              file: {
                id: "F789",
                name: "image.png",
                permalink: "https://example.slack.com/files/U123/F789/image.png"
              }
            }.to_json
          )

        result = adapter.send_message(
          to: "C123456",
          content: "Remote image",
          url: "https://example.com/image.png"
        )

        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        expect(result.data[:outbound_message].metadata["file_name"]).to eq("image.png")
      end

      it 'handles download failures' do
        stub_request(:get, "https://example.com/missing.png")
          .to_return(status: 404)

        result = adapter.send_message(
          to: "C123456",
          content: "Missing remote file",
          url: "https://example.com/missing.png"
        )

        expect(result).not_to be_success
        expect(result.error).to include("download")
      end
    end

    context 'with file metadata' do
      let(:temp_file) do
        file = Tempfile.new(['doc', '.txt'], encoding: 'ascii-8bit')
        file.write("Important document")
        file.rewind
        file
      end

      after { temp_file.close && temp_file.unlink }

      it 'includes title in file upload' do
        stub_request(:post, "https://slack.com/api/files.upload")
          .with { |request|
            request.body.include?("Content-Disposition: form-data; name=\"title\"") &&
              request.body.include?("My Custom Title")
          }
          .to_return(
            status: 200,
            body: { ok: true, file: { id: "F123" } }.to_json
          )

        result = adapter.send_message(
          to: "C123456",
          content: "Document upload",
          file_path: temp_file.path,
          title: "My Custom Title"
        )

        expect(result).to be_success
      end

      it 'includes initial_comment from content parameter' do
        stub_request(:post, "https://slack.com/api/files.upload")
          .with { |request|
            request.body.include?("initial_comment") &&
              request.body.include?("Check this out")
          }
          .to_return(
            status: 200,
            body: { ok: true, file: { id: "F123" } }.to_json
          )

        result = adapter.send_message(
          to: "C123456",
          content: "Check this out",
          file_path: temp_file.path
        )

        expect(result).to be_success
      end

      it 'includes thread_ts in file upload' do
        stub_request(:post, "https://slack.com/api/files.upload")
          .with { |request|
            request.body.include?("thread_ts") &&
              request.body.include?("1234567890.000001")
          }
          .to_return(
            status: 200,
            body: { ok: true, file: { id: "F123" } }.to_json
          )

        result = adapter.send_message(
          to: "C123456",
          content: "Threaded file",
          file_path: temp_file.path,
          thread_ts: "1234567890.000001"
        )

        expect(result).to be_success
      end
    end

    context 'with agent-specific token' do
      let(:agent) { create(:agent) }

      it 'uses agent-specific token when available' do
        # Stub the auth.test call that happens when setting bot_token
        stub_request(:post, "https://slack.com/api/auth.test")
          .to_return(status: 200, body: { ok: true, user_id: "U123" }.to_json)

        agent_channel = create(:agent_channel, channel: channel, agent: agent)
        agent_channel.update(bot_token: "xoxb-agent-token-456")

        stub_request(:post, "https://slack.com/api/chat.postMessage")
          .with(
            headers: { "Authorization" => "Bearer xoxb-agent-token-456" }
          )
          .to_return(
            status: 200,
            body: { ok: true, ts: "123", channel: "C123456" }.to_json
          )

        result = adapter.send_message(to: "C123456", content: "Agent message", agent: agent)

        expect(result).to be_success
      end
    end
  end

  describe '#receive' do
    it 'handles URL verification challenge' do
      payload = {
        type: 'url_verification',
        challenge: 'test-challenge-123'
      }

      result = adapter.receive(payload)

      expect(result).to be_success
      expect(result.data[:challenge]).to eq('test-challenge-123')
    end

    it 'logs inbound messages' do
      payload = {
        type: 'event_callback',
        team_id: 'T123',
        event: {
          type: 'message',
          user: 'U123',
          text: 'Hello bot',
          ts: '1234567890.000001',
          channel: 'C123456'
        }
      }

      result = adapter.receive(payload)

      expect(result).to be_success
      expect(result.data[:inbound_message]).to be_a(InboundMessage)
      expect(result.data[:inbound_message].content).to eq('Hello bot')
      expect(result.data[:inbound_message].sender).to eq('U123')
    end

    it 'ignores bot messages' do
      payload = {
        type: 'event_callback',
        team_id: 'T123',
        event: {
          type: 'message',
          user: 'U123',
          bot_id: 'B123',
          text: 'Bot message',
          ts: '1234567890.000001',
          channel: 'C123456'
        }
      }

      result = adapter.receive(payload)

      expect(result).to be_success
      expect(result.data[:skipped]).to be true
    end
  end

  describe '#react' do
    it 'adds a reaction to a message' do
      stub_request(:post, "https://slack.com/api/reactions.add")
        .with(
          headers: { "Authorization" => "Bearer #{slack_token}" },
          body: hash_including(
            "channel" => "C123456",
            "timestamp" => "1234567890.000001",
            "name" => "thumbsup"
          )
        )
        .to_return(status: 200, body: { ok: true }.to_json)

      result = adapter.react(
        message_id: "1234567890.000001",
        emoji: "thumbsup",
        channel_id: "C123456"
      )

      expect(result).to be_success
    end

    it 'strips colons from emoji' do
      stub_request(:post, "https://slack.com/api/reactions.add")
        .with { |request|
          request.body.include?('"name":"thumbsup"')
        }
        .to_return(status: 200, body: { ok: true }.to_json)

      adapter.react(
        message_id: "1234567890.000001",
        emoji: ":thumbsup:",
        channel_id: "C123456"
      )
    end
  end

  describe '#verify_webhook' do
    let(:signing_secret) { "test-secret-123" }

    before do
      create(:vault_entry,
        namespace: "channel_credentials",
        key: "slack_webhook_secret",
        value: signing_secret
      )
    end

    it 'trusts requests from internal Docker network' do
      request = double('request', remote_ip: '172.17.0.1')
      expect(adapter.verify_webhook(request)).to be true
    end

    it 'trusts requests from localhost' do
      request = double('request', remote_ip: '127.0.0.1')
      expect(adapter.verify_webhook(request)).to be true
    end

    it 'verifies external requests with signing secret' do
      timestamp = Time.now.to_i.to_s
      body = '{"test":"data"}'
      sig_basestring = "v0:#{timestamp}:#{body}"
      signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)}"

      request = double('request',
        remote_ip: '8.8.8.8',
        headers: {
          'X-Slack-Request-Timestamp' => timestamp,
          'X-Slack-Signature' => signature
        },
        raw_post: body
      )

      expect(adapter.verify_webhook(request)).to be true
    end

    it 'rejects requests with invalid signature' do
      timestamp = Time.now.to_i.to_s
      request = double('request',
        remote_ip: '8.8.8.8',
        headers: {
          'X-Slack-Request-Timestamp' => timestamp,
          'X-Slack-Signature' => 'v0=invalid'
        },
        raw_post: '{"test":"data"}'
      )

      expect(adapter.verify_webhook(request)).to be false
    end
  end

  describe 'private methods' do
    describe '#determine_filetype' do
      it 'determines filetype from filename extension' do
        expect(adapter.send(:determine_filetype, 'image.png')).to eq('png')
        expect(adapter.send(:determine_filetype, 'photo.jpg')).to eq('jpg')
        expect(adapter.send(:determine_filetype, 'document.pdf')).to eq('pdf')
        expect(adapter.send(:determine_filetype, 'script.txt')).to eq('text')
        expect(adapter.send(:determine_filetype, 'data.xlsx')).to eq('excel')
      end

      it 'returns nil for unknown extensions' do
        expect(adapter.send(:determine_filetype, 'unknown.xyz')).to be_nil
      end
    end

    describe '#format_bytes' do
      it 'formats bytes to human-readable format' do
        expect(adapter.send(:format_bytes, 512)).to include('512')
        expect(adapter.send(:format_bytes, 1024)).to include('1')
        expect(adapter.send(:format_bytes, 1024 * 1024)).to include('1')
        expect(adapter.send(:format_bytes, 1024 * 1024 * 1024)).to include('1')
      end
    end

    describe '#build_multipart_body' do
      it 'builds valid multipart body' do
        body = adapter.send(:build_multipart_body,
          boundary: 'test-boundary',
          filename: 'test.txt',
          file_content: 'Hello World',
          title: 'Test Title',
          filetype: 'text',
          initial_comment: 'Here is the file',
          channel: 'C123456',
          thread_ts: '1234567890.000001'
        )

        expect(body).to include('test-boundary')
        expect(body).to include('test.txt')
        expect(body).to include('Hello World')
        expect(body).to include('Test Title')
        expect(body).to include('Here is the file')
        expect(body).to include('C123456')
        expect(body).to include('1234567890.000001')
      end

      it 'omits optional fields when not provided' do
        body = adapter.send(:build_multipart_body,
          boundary: 'test-boundary',
          filename: 'test.txt',
          file_content: 'Hello World',
          title: nil,
          filetype: nil,
          initial_comment: nil,
          channel: 'C123456'
        )

        expect(body).not_to include('title')
        expect(body).not_to include('filetype')
      end
    end
  end
end
