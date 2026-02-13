# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::CustomScriptExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: config, agent: nil) }

  describe '#call' do
    context 'with valid script template' do
      let(:config) { { "script_template" => "echo 'Hello {{name}}!'" } }
      let(:input) { { "name" => "World" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['Hello World!', '', double(exitstatus: 0)])
      end

      it 'returns success with script output' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq('Hello World!')
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'interpolates template parameters' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          { "HOME" => "/workspace", "PATH" => "/usr/local/bin:/usr/bin:/bin" },
          "bash", "-c", "echo 'Hello World!'",
          chdir: "/workspace"
        )
      end

      it 'executes with proper environment' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          hash_including("HOME" => "/workspace"),
          "bash", "-c", anything,
          chdir: "/workspace"
        )
      end
    end

    context 'with multiple parameters' do
      let(:config) { { "script_template" => "curl -X {{method}} {{url}} -H 'Content-Type: {{content_type}}'" } }
      let(:input) { { "method" => "POST", "url" => "https://api.example.com", "content_type" => "application/json" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['{"status":"ok"}', '', double(exitstatus: 0)])
      end

      it 'interpolates multiple parameters' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything,
          "bash", "-c", "curl -X POST https://api.example.com -H 'Content-Type: application/json'",
          anything
        )
      end
    end

    context 'with special characters in parameters' do
      let(:config) { { "script_template" => "echo {{message}}" } }
      let(:input) { { "message" => "Hello; rm -rf /" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['Hello; rm -rf /', '', double(exitstatus: 0)])
      end

      it 'shell-escapes dangerous input' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything,
          "bash", "-c", "echo Hello\\;\\ rm\\ -rf\\ /",
          anything
        )
      end
    end

    context 'with missing parameters' do
      let(:config) { { "script_template" => "echo 'Hello {{name}}! You are {{age}} years old.'" } }
      let(:input) { { "name" => "Alice" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['Hello Alice! You are  years old.', '', double(exitstatus: 0)])
      end

      it 'replaces missing parameters with empty string' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything,
          "bash", "-c", "echo 'Hello Alice! You are  years old.'",
          anything
        )
      end
    end

    context 'with symbol keys in input' do
      let(:config) { { "script_template" => "echo {{name}}" } }
      let(:input) { { name: "World" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['World', '', double(exitstatus: 0)])
      end

      it 'handles symbol keys' do
        result = executor.call
        expect(result).to be_success
        expect(Open3).to have_received(:capture3).with(
          anything, "bash", "-c", "echo World", anything
        )
      end
    end

    context 'without script template' do
      let(:config) { {} }
      let(:input) { { "name" => "World" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No script template configured for this tool")
      end
    end

    context 'with empty script template' do
      let(:config) { { "script_template" => "  " } }
      let(:input) { { "name" => "World" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No script template configured for this tool")
      end
    end

    context 'when script fails' do
      let(:config) { { "script_template" => "exit 1" } }
      let(:input) { {} }

      before do
        allow(Open3).to receive(:capture3).and_return(['', 'Command failed', double(exitstatus: 1)])
      end

      it 'returns failure with exit code' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Script exited with code 1")
        expect(result.data[:output]).to include("STDERR: Command failed")
        expect(result.data[:exit_code]).to eq(1)
      end
    end

    context 'when script produces both stdout and stderr' do
      let(:config) { { "script_template" => "echo 'success' && echo 'warning' >&2" } }
      let(:input) { {} }

      before do
        allow(Open3).to receive(:capture3).and_return(['success', 'warning', double(exitstatus: 0)])
      end

      it 'includes stderr in output' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("success")
        expect(result.data[:output]).to include("STDERR: warning")
      end
    end

    context 'when script times out' do
      let(:config) { { "script_template" => "sleep 100" } }
      let(:input) { {} }

      before do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      end

      it 'returns failure with timeout message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Script timed out after 60s")
      end
    end

    context 'when execution raises exception' do
      let(:config) { { "script_template" => "echo test" } }
      let(:input) { {} }

      before do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("Execution error"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Script execution failed: Execution error")
      end
    end

    context 'with large output' do
      let(:config) { { "script_template" => "echo test" } }
      let(:input) { {} }
      let(:large_output) { 'x' * 60_000 }

      before do
        allow(Open3).to receive(:capture3).and_return([large_output, '', double(exitstatus: 0)])
      end

      it 'truncates output to 50KB' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output].length).to be <= 50_000
      end
    end

    context 'with complex template' do
      let(:config) do
        {
          "script_template" => <<~SCRIPT.strip
            cd {{directory}}
            {{command}} --format={{format}} --output={{output_file}}
            cat {{output_file}}
          SCRIPT
        }
      end
      let(:input) do
        {
          "directory" => "/tmp",
          "command" => "ls",
          "format" => "json",
          "output_file" => "result.json"
        }
      end

      before do
        allow(Open3).to receive(:capture3).and_return(['{"files": []}', '', double(exitstatus: 0)])
      end

      it 'handles multiline templates' do
        result = executor.call
        expect(result).to be_success
        
        expected_command = "cd /tmp\nls --format=json --output=result.json\ncat result.json"
        expect(Open3).to have_received(:capture3).with(
          anything, "bash", "-c", expected_command, anything
        )
      end
    end

    context 'with quotes in parameters' do
      let(:config) { { "script_template" => "echo {{message}}" } }
      let(:input) { { "message" => "He said \"Hello world\"" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['He said "Hello world"', '', double(exitstatus: 0)])
      end

      it 'properly escapes quotes' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything,
          "bash", "-c", "echo He\\ said\\ \\\"Hello\\ world\\\"",
          anything
        )
      end
    end

    context 'when status is nil' do
      let(:config) { { "script_template" => "echo test" } }
      let(:input) { {} }

      before do
        allow(Open3).to receive(:capture3).and_return(['output', '', nil])
      end

      it 'defaults exit code to 1' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Script exited with code 1")
        expect(result.data[:exit_code]).to eq(1)
      end
    end
  end

  describe '#interpolate_template' do
    let(:config) { {} }
    let(:input) { { "name" => "test", "value" => "123" } }

    it 'interpolates template parameters' do
      result = executor.send(:interpolate_template, "Hello {{name}} with {{value}}")
      expect(result).to eq("Hello test with 123")
    end

    it 'handles missing parameters' do
      result = executor.send(:interpolate_template, "Hello {{name}} {{missing}}")
      expect(result).to eq("Hello test ")
    end

    it 'shell-escapes parameter values' do
      executor.instance_variable_set(:@input, { "unsafe" => "test; rm -rf /" })
      result = executor.send(:interpolate_template, "run {{unsafe}}")
      expect(result).to eq("run test\\;\\ rm\\ -rf\\ /")
    end
  end
end