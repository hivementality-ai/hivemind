# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CloudStorage::ConfigureRemote do
  let(:backend) { "drive" }
  let(:remote_name) { "test_remote" }
  let(:token) { '{"access_token":"ya29.abc123","token_type":"Bearer","refresh_token":"1//def456"}' }

  before do
    # Mock file system operations
    allow(FileUtils).to receive(:mkdir_p)
    allow(File).to receive(:exist?).and_return(false)
    allow(File).to receive(:read).and_return("")
    allow(File).to receive(:write)
  end

  describe '#call' do
    let(:service) { described_class.new(backend: backend, remote_name: remote_name, token: token) }

    describe 'input validation' do
      context 'with unknown backend' do
        let(:service) { described_class.new(backend: "unknown", remote_name: remote_name) }

        it 'returns failure for unknown backend' do
          result = service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("Unknown backend: unknown")
        end
      end

      context 'with empty remote name' do
        let(:service) { described_class.new(backend: backend, remote_name: "") }

        it 'returns failure for empty remote name' do
          result = service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("Remote name is required")
        end
      end

      context 'with invalid characters in remote name' do
        let(:service) { described_class.new(backend: backend, remote_name: "test@remote!") }

        it 'sanitizes remote name' do
          allow(service).to receive(:configure_drive).and_return({ success: true })
          
          service.call
          
          # Should strip invalid characters, keeping only alphanumeric, underscore, and dash
          expect(service.instance_variable_get(:@remote_name)).to eq("testremote")
        end
      end

      it 'creates rclone config directory' do
        allow(service).to receive(:configure_drive).and_return({ success: true })
        
        service.call
        
        expect(FileUtils).to have_received(:mkdir_p).with(described_class::RCLONE_CONFIG_DIR)
      end
    end

    describe 'Google Drive configuration' do
      let(:backend) { "drive" }

      context 'with valid token' do
        it 'configures drive remote successfully' do
          allow(service).to receive(:rclone_create).and_return({ success: true, data: { remote: remote_name } })
          
          result = service.call
          
          expect(service).to have_received(:rclone_create).with("drive", token: token, scope: "drive")
          expect(result[:success]).to be true
        end
      end

      context 'without token' do
        let(:token) { nil }

        it 'returns failure with authorization instructions' do
          result = service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq('Token required — run `rclone authorize "drive"` locally and paste the result')
        end
      end

      context 'with blank token' do
        let(:token) { "   " }

        it 'returns failure for blank token' do
          result = service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to include("Token required")
        end
      end
    end

    describe 'S3 configuration' do
      let(:backend) { "s3" }
      let(:params) do
        {
          access_key_id: "AKIATEST123",
          secret_access_key: "secretkey123",
          region: "us-west-2"
        }
      end
      let(:service) { described_class.new(backend: backend, remote_name: remote_name, params: params) }

      context 'with valid credentials' do
        it 'configures S3 remote successfully' do
          allow(service).to receive(:run_rclone).and_return({ success: true })
          
          result = service.call
          
          expected_args = [
            "rclone", "config", "create", remote_name, "s3",
            "provider", "AWS",
            "access_key_id", "AKIATEST123",
            "secret_access_key", "secretkey123",
            "region", "us-west-2",
            "--config", described_class::RCLONE_CONFIG_PATH
          ]
          
          expect(service).to have_received(:run_rclone).with(expected_args)
          expect(result[:success]).to be true
        end

        it 'uses default provider and region when not specified' do
          minimal_params = { access_key_id: "KEY", secret_access_key: "SECRET" }
          minimal_service = described_class.new(backend: backend, remote_name: remote_name, params: minimal_params)
          allow(minimal_service).to receive(:run_rclone).and_return({ success: true })
          
          minimal_service.call
          
          expect(minimal_service).to have_received(:run_rclone) do |args|
            expect(args).to include("provider", "AWS")
            expect(args).to include("region", "us-east-1")
          end
        end

        it 'includes endpoint when provided' do
          params_with_endpoint = params.merge(endpoint: "https://s3.example.com")
          service_with_endpoint = described_class.new(backend: backend, remote_name: remote_name, params: params_with_endpoint)
          allow(service_with_endpoint).to receive(:run_rclone).and_return({ success: true })
          
          service_with_endpoint.call
          
          expect(service_with_endpoint).to have_received(:run_rclone) do |args|
            expect(args).to include("endpoint", "https://s3.example.com")
          end
        end
      end

      context 'with missing credentials' do
        it 'returns failure for missing access key' do
          invalid_params = params.except(:access_key_id)
          invalid_service = described_class.new(backend: backend, remote_name: remote_name, params: invalid_params)
          
          result = invalid_service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("access_key_id and secret_access_key required")
        end

        it 'returns failure for missing secret key' do
          invalid_params = params.except(:secret_access_key)
          invalid_service = described_class.new(backend: backend, remote_name: remote_name, params: invalid_params)
          
          result = invalid_service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("access_key_id and secret_access_key required")
        end

        it 'handles empty string credentials' do
          empty_params = { access_key_id: "  ", secret_access_key: "" }
          empty_service = described_class.new(backend: backend, remote_name: remote_name, params: empty_params)
          
          result = empty_service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("access_key_id and secret_access_key required")
        end
      end
    end

    describe 'Backblaze B2 configuration' do
      let(:backend) { "b2" }
      let(:params) { { account: "test_account_id", key: "test_application_key" } }
      let(:service) { described_class.new(backend: backend, remote_name: remote_name, params: params) }

      context 'with valid credentials' do
        it 'configures B2 remote successfully' do
          allow(service).to receive(:run_rclone).and_return({ success: true })
          
          result = service.call
          
          expected_args = [
            "rclone", "config", "create", remote_name, "b2",
            "account", "test_account_id",
            "key", "test_application_key",
            "--config", described_class::RCLONE_CONFIG_PATH
          ]
          
          expect(service).to have_received(:run_rclone).with(expected_args)
          expect(result[:success]).to be true
        end
      end

      context 'with missing credentials' do
        it 'returns failure for missing account' do
          invalid_params = params.except(:account)
          invalid_service = described_class.new(backend: backend, remote_name: remote_name, params: invalid_params)
          
          result = invalid_service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("account and key required")
        end

        it 'returns failure for missing key' do
          invalid_params = params.except(:key)
          invalid_service = described_class.new(backend: backend, remote_name: remote_name, params: invalid_params)
          
          result = invalid_service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("account and key required")
        end
      end
    end

    describe 'SFTP configuration' do
      let(:backend) { "sftp" }
      let(:params) { { host: "ftp.example.com", user: "testuser" } }
      let(:service) { described_class.new(backend: backend, remote_name: remote_name, params: params) }

      context 'with valid basic credentials' do
        it 'configures SFTP remote successfully' do
          allow(service).to receive(:run_rclone).and_return({ success: true })
          
          result = service.call
          
          expected_args = [
            "rclone", "config", "create", remote_name, "sftp",
            "host", "ftp.example.com",
            "user", "testuser",
            "port", "22",
            "--config", described_class::RCLONE_CONFIG_PATH
          ]
          
          expect(service).to have_received(:run_rclone).with(expected_args)
          expect(result[:success]).to be true
        end

        it 'uses custom port when provided' do
          params_with_port = params.merge(port: "2222")
          service_with_port = described_class.new(backend: backend, remote_name: remote_name, params: params_with_port)
          allow(service_with_port).to receive(:run_rclone).and_return({ success: true })
          
          service_with_port.call
          
          expect(service_with_port).to have_received(:run_rclone) do |args|
            expect(args).to include("port", "2222")
          end
        end

        it 'includes password when provided' do
          params_with_pass = params.merge(pass: "secretpass")
          service_with_pass = described_class.new(backend: backend, remote_name: remote_name, params: params_with_pass)
          allow(service_with_pass).to receive(:run_rclone).and_return({ success: true })
          allow(service_with_pass).to receive(:rclone_obscure).with("secretpass").and_return("obscured_pass")
          
          service_with_pass.call
          
          expect(service_with_pass).to have_received(:run_rclone) do |args|
            expect(args).to include("pass", "obscured_pass")
          end
        end

        it 'includes key file when provided' do
          params_with_key = params.merge(key_file: "/home/user/.ssh/id_rsa")
          service_with_key = described_class.new(backend: backend, remote_name: remote_name, params: params_with_key)
          allow(service_with_key).to receive(:run_rclone).and_return({ success: true })
          
          service_with_key.call
          
          expect(service_with_key).to have_received(:run_rclone) do |args|
            expect(args).to include("key_file", "/home/user/.ssh/id_rsa")
          end
        end
      end

      context 'with missing required fields' do
        it 'returns failure for missing host' do
          invalid_params = params.except(:host)
          invalid_service = described_class.new(backend: backend, remote_name: remote_name, params: invalid_params)
          
          result = invalid_service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("host and user required")
        end

        it 'returns failure for missing user' do
          invalid_params = params.except(:user)
          invalid_service = described_class.new(backend: backend, remote_name: remote_name, params: invalid_params)
          
          result = invalid_service.call
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("host and user required")
        end
      end
    end

    describe 'OAuth backends (Dropbox, OneDrive)' do
      %w[dropbox onedrive].each do |oauth_backend|
        context "with #{oauth_backend}" do
          let(:backend) { oauth_backend }

          context 'with valid token' do
            it "configures #{oauth_backend} remote successfully" do
              allow(service).to receive(:rclone_create).and_return({ success: true })
              
              result = service.call
              
              expect(service).to have_received(:rclone_create).with(oauth_backend, token: token)
              expect(result[:success]).to be true
            end
          end

          context 'without token' do
            let(:token) { nil }

            it 'returns failure with authorization instructions' do
              result = service.call
              
              expect(result[:success]).to be false
              expect(result[:error]).to eq("Token required — run `rclone authorize \"#{oauth_backend}\"` locally and paste the result")
            end
          end
        end
      end
    end
  end

  describe 'class methods' do
    describe '.list_remotes' do
      context 'when config file exists' do
        before do
          allow(File).to receive(:exist?).with(described_class::RCLONE_CONFIG_PATH).and_return(true)
        end

        it 'returns list of remotes from rclone' do
          allow(Open3).to receive(:capture3).with(
            "rclone", "listremotes", "--config", described_class::RCLONE_CONFIG_PATH
          ).and_return(["remote1:\nremote2:\nremote3:\n", "", double(success?: true)])

          remotes = described_class.list_remotes
          
          expect(remotes).to eq(["remote1", "remote2", "remote3"])
        end

        it 'returns empty array when rclone command fails' do
          allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

          remotes = described_class.list_remotes
          
          expect(remotes).to eq([])
        end

        it 'handles empty output' do
          allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])

          remotes = described_class.list_remotes
          
          expect(remotes).to eq([])
        end
      end

      context 'when config file does not exist' do
        before do
          allow(File).to receive(:exist?).with(described_class::RCLONE_CONFIG_PATH).and_return(false)
        end

        it 'returns empty array' do
          remotes = described_class.list_remotes
          expect(remotes).to eq([])
        end

        it 'does not call rclone' do
          expect(Open3).not_to receive(:capture3)
          described_class.list_remotes
        end
      end
    end

    describe '.remote_info' do
      let(:remote_name) { "test_remote" }

      context 'when remote info is available' do
        let(:remote_info) { { "total" => 1000000, "used" => 500000, "free" => 500000 } }

        it 'returns parsed JSON info' do
          allow(Open3).to receive(:capture3).with(
            "rclone", "about", "#{remote_name}:", "--config", described_class::RCLONE_CONFIG_PATH, "--json"
          ).and_return([remote_info.to_json, "", double(success?: true)])

          info = described_class.remote_info(remote_name)
          
          expect(info).to eq(remote_info)
        end
      end

      context 'when rclone command fails' do
        it 'returns nil' do
          allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

          info = described_class.remote_info(remote_name)
          
          expect(info).to be_nil
        end
      end

      context 'when JSON parsing fails' do
        it 'returns nil for invalid JSON' do
          allow(Open3).to receive(:capture3).and_return(["invalid json", "", double(success?: true)])

          info = described_class.remote_info(remote_name)
          
          expect(info).to be_nil
        end
      end
    end

    describe '.delete_remote' do
      let(:remote_name) { "test_remote" }

      it 'returns true when deletion succeeds' do
        allow(Open3).to receive(:capture3).with(
          "rclone", "config", "delete", remote_name, "--config", described_class::RCLONE_CONFIG_PATH
        ).and_return(["", "", double(success?: true)])

        result = described_class.delete_remote(remote_name)
        
        expect(result).to be true
      end

      it 'returns false when deletion fails' do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        result = described_class.delete_remote(remote_name)
        
        expect(result).to be false
      end
    end

    describe '.config_path' do
      it 'returns the rclone config path' do
        expect(described_class.config_path).to eq(described_class::RCLONE_CONFIG_PATH)
      end
    end
  end

  describe 'helper methods' do
    let(:service) { described_class.new(backend: backend, remote_name: remote_name) }

    describe '#inject_token' do
      let(:existing_config) do
        <<~CONFIG
          [test_remote]
          type = drive
          scope = drive

          [other_remote]
          type = s3
          provider = AWS
        CONFIG
      end

      before do
        allow(File).to receive(:exist?).with(described_class::RCLONE_CONFIG_PATH).and_return(true)
        allow(File).to receive(:read).with(described_class::RCLONE_CONFIG_PATH).and_return(existing_config)
      end

      it 'injects token into the correct remote section' do
        result = service.send(:inject_token, "test_remote", token)

        expect(File).to have_received(:write) do |path, content|
          expect(path).to eq(described_class::RCLONE_CONFIG_PATH)
          expect(content).to include("[test_remote]\ntoken = #{token}")
          expect(content).to include("[other_remote]") # Should preserve other remotes
        end
        
        expect(result[:success]).to be true
        expect(result[:message]).to include("configured successfully")
      end

      it 'returns failure when config file does not exist' do
        allow(File).to receive(:exist?).and_return(false)

        result = service.send(:inject_token, "test_remote", token)
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Config file not found")
      end

      it 'returns failure when remote section is not found' do
        result = service.send(:inject_token, "nonexistent_remote", token)
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Remote section not found in config")
      end
    end

    describe '#rclone_obscure' do
      it 'obscures password using rclone' do
        allow(Open3).to receive(:capture3).with("rclone", "obscure", "mypassword").and_return(
          ["obscured_password", "", double(success?: true)]
        )

        result = service.send(:rclone_obscure, "mypassword")
        
        expect(result).to eq("obscured_password")
      end

      it 'returns original password when obscure fails' do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        result = service.send(:rclone_obscure, "mypassword")
        
        expect(result).to eq("mypassword")
      end
    end

    describe '#run_rclone' do
      let(:args) { ["rclone", "config", "create", "test"] }

      it 'returns success when rclone succeeds' do
        allow(Open3).to receive(:capture3).with(*args).and_return(
          ["Remote created", "", double(success?: true)]
        )

        result = service.send(:run_rclone, args)
        
        expect(result[:success]).to be true
        expect(result[:message]).to include("configured successfully")
      end

      it 'returns failure when rclone fails' do
        allow(Open3).to receive(:capture3).with(*args).and_return(
          ["", "Failed to create remote", double(success?: false)]
        )

        result = service.send(:run_rclone, args)
        
        expect(result[:success]).to be false
        expect(result[:error]).to include("rclone config failed: Failed to create remote")
      end

      it 'prefers stderr over stdout for error messages' do
        allow(Open3).to receive(:capture3).with(*args).and_return(
          ["Some stdout", "Error in stderr", double(success?: false)]
        )

        result = service.send(:run_rclone, args)
        
        expect(result[:error]).to include("Error in stderr")
      end

      it 'uses stdout when stderr is empty' do
        allow(Open3).to receive(:capture3).with(*args).and_return(
          ["Error in stdout", "", double(success?: false)]
        )

        result = service.send(:run_rclone, args)
        
        expect(result[:error]).to include("Error in stdout")
      end
    end
  end

  describe 'constants' do
    it 'defines supported backends with correct structure' do
      expect(described_class::BACKENDS).to be_a(Hash)
      expect(described_class::BACKENDS).to be_frozen
      
      described_class::BACKENDS.each do |backend, config|
        expect(config).to have_key(:name)
        expect(config).to have_key(:rclone_type)
        expect(config).to have_key(:needs_token)
        expect(config[:needs_token]).to be_in([true, false])
      end
    end

    it 'includes expected backends' do
      expected_backends = %w[drive s3 dropbox onedrive b2 sftp]
      expect(described_class::BACKENDS.keys).to match_array(expected_backends)
    end

    it 'defines config paths' do
      expect(described_class::RCLONE_CONFIG_DIR).to eq("/rails/storage/rclone")
      expect(described_class::RCLONE_CONFIG_PATH).to eq("/rails/storage/rclone/rclone.conf")
    end
  end
end