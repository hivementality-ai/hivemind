# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::ShellExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    allow(FileUtils).to receive(:mkdir_p)
    allow(File).to receive(:write)
    allow(File).to receive(:chmod)
    allow(File).to receive(:delete)
    allow(File).to receive(:exist?).and_return(false)
    allow(SecureRandom).to receive(:hex).and_return('12345678')
  end

  describe '#call' do
    context 'with valid command' do
      let(:input) { { "command" => "echo 'hello world'" } }

      context 'when Docker is available' do
        before do
          allow_any_instance_of(described_class).to receive(:docker_available?).and_return(true)
          allow(Open3).to receive(:capture3).and_return(['hello world', '', double(success?: true)])
          allow(File).to receive(:exist?).with('/workspace/.hivemind/exec/12345678.exit').and_return(true)
          allow(File).to receive(:read).with('/workspace/.hivemind/exec/12345678.exit').and_return('0')
        end

        it 'returns success with command output' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq('hello world')
          expect(result.data[:exit_code]).to eq(0)
        end

        it 'creates exec directory' do
          executor.call
          expect(FileUtils).to have_received(:mkdir_p).with('/workspace/.hivemind/exec')
        end

        it 'writes script to shared volume' do
          executor.call
          expect(File).to have_received(:write).with('/workspace/.hivemind/exec/12345678.sh', anything)
        end

        it 'sets script permissions' do
          executor.call
          expect(File).to have_received(:chmod).with(0o755, '/workspace/.hivemind/exec/12345678.sh')
        end

        it 'executes docker command' do
          executor.call
          expect(Open3).to have_received(:capture3).with(
            "docker", "exec", "hivemind-workspace-1", "bash", "-c", anything
          )
        end

        it 'cleans up temporary files' do
          allow(File).to receive(:exist?).and_return(true)
          executor.call
          expect(File).to have_received(:delete).exactly(3).times
        end
      end

      context 'when Docker is not available' do
        before do
          allow_any_instance_of(described_class).to receive(:docker_available?).and_return(false)
          allow(Open3).to receive(:capture3).and_return(['hello world', '', double(exitstatus: 0)])
        end

        it 'falls back to direct execution' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq('hello world')
          expect(result.data[:exit_code]).to eq(0)
        end

        it 'executes with proper environment' do
          executor.call
          expect(Open3).to have_received(:capture3).with(
            { "HOME" => "/workspace", "PATH" => "/usr/local/bin:/usr/bin:/bin" },
            "bash", "-c", "echo 'hello world'",
            chdir: "/workspace"
          )
        end
      end

      context 'with GitHub token configured' do
        before do
          allow_any_instance_of(described_class).to receive(:docker_available?).and_return(true)
          allow(Open3).to receive(:capture3).and_return(['', '', double(success?: true)])
          allow(File).to receive(:exist?).and_return(true)
          allow(File).to receive(:read).and_return('0')

          create(:vault_entry, namespace: 'github', key: 'token', value: 'ghp_test_token')
        end

        it 'includes GitHub token in script' do
          script_content = nil
          allow(File).to receive(:write) do |path, content|
            script_content = content if path.include?('.sh')
          end

          executor.call

          expect(script_content).to include("export GH_TOKEN='ghp_test_token'")
          expect(script_content).to include("export GITHUB_TOKEN='ghp_test_token'")
        end
      end
    end

    context 'without command' do
      let(:input) { {} }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq('No command provided')
      end
    end

    context 'with empty command' do
      let(:input) { { "command" => "  " } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq('No command provided')
      end
    end

    context 'when command times out' do
      let(:input) { { "command" => "sleep 100" } }

      before do
        allow_any_instance_of(described_class).to receive(:docker_available?).and_return(true)
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      end

      it 'returns failure with timeout message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq('Command timed out after 60s')
      end
    end

    context 'when execution fails' do
      let(:input) { { "command" => "false" } }

      before do
        allow_any_instance_of(described_class).to receive(:docker_available?).and_return(true)
        allow(Open3).to receive(:capture3).and_raise(StandardError.new('Execution error'))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq('Shell execution failed: Execution error')
      end
    end

    context 'with large output' do
      let(:input) { { "command" => "echo 'test'" } }
      let(:large_output) { 'x' * 60_000 }

      before do
        allow_any_instance_of(described_class).to receive(:docker_available?).and_return(true)
        allow(Open3).to receive(:capture3).and_return([large_output, '', double(success?: true)])
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('0')
      end

      it 'truncates output to 50KB' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output].length).to be <= 50_000
      end
    end

    context 'with stderr output' do
      let(:input) { { "command" => "echo 'error' >&2" } }

      before do
        allow_any_instance_of(described_class).to receive(:docker_available?).and_return(true)
        allow(Open3).to receive(:capture3).and_return(['', 'error message', double(success?: false)])
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('1')
      end

      it 'includes stderr in output' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include('STDERR: error message')
        expect(result.data[:exit_code]).to eq(1)
      end
    end
  end

  describe '#docker_available?' do
    it 'returns true when docker info succeeds' do
      allow(Open3).to receive(:capture3).with("docker", "info").and_return(['', '', double(success?: true)])
      expect(executor.send(:docker_available?)).to be true
    end

    it 'returns false when docker info fails' do
      allow(Open3).to receive(:capture3).with("docker", "info").and_return(['', '', double(success?: false)])
      expect(executor.send(:docker_available?)).to be false
    end

    it 'returns false when docker is not found' do
      allow(Open3).to receive(:capture3).with("docker", "info").and_raise(Errno::ENOENT)
      expect(executor.send(:docker_available?)).to be false
    end

    it 'caches the result' do
      allow(Open3).to receive(:capture3).with("docker", "info").and_return(['', '', double(success?: true)])
      executor.send(:docker_available?)
      executor.send(:docker_available?)
      expect(Open3).to have_received(:capture3).once
    end
  end
end