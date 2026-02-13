# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::FileWriteExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  describe '#call' do
    context 'with valid path and content' do
      let(:input) { { "path" => "test/file.txt", "content" => "Hello, world!" } }

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(File).to receive(:dirname).and_return("/workspace/test")
      end

      it 'returns success with file info' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Wrote 13 bytes to test/file.txt")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'creates directory structure' do
        executor.call
        expect(FileUtils).to have_received(:mkdir_p).with("/workspace/test")
      end

      it 'writes content to file' do
        executor.call
        expect(File).to have_received(:write).with("/workspace/test/file.txt", "Hello, world!")
      end
    end

    context 'with absolute path within workspace' do
      let(:input) { { "path" => "/workspace/documents/file.txt", "content" => "test content" } }

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(File).to receive(:dirname).and_return("/workspace/documents")
      end

      it 'writes to absolute path' do
        result = executor.call
        expect(result).to be_success
        expect(File).to have_received(:write).with("/workspace/documents/file.txt", "test content")
      end
    end

    context 'with empty content' do
      let(:input) { { "path" => "empty.txt", "content" => "" } }

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(File).to receive(:dirname).and_return("/workspace")
      end

      it 'creates empty file' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Wrote 0 bytes to empty.txt")
        expect(File).to have_received(:write).with("/workspace/empty.txt", "")
      end
    end

    context 'without path parameter' do
      let(:input) { { "content" => "some content" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No path provided")
      end
    end

    context 'with empty path' do
      let(:input) { { "path" => "  ", "content" => "content" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No path provided")
      end
    end

    context 'without content parameter' do
      let(:input) { { "path" => "test.txt" } }

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(File).to receive(:dirname).and_return("/workspace")
      end

      it 'writes empty string' do
        result = executor.call
        expect(result).to be_success
        expect(File).to have_received(:write).with("/workspace/test.txt", "")
      end
    end

    context 'with path outside workspace' do
      let(:input) { { "path" => "/etc/passwd", "content" => "malicious" } }

      it 'returns failure for absolute path outside workspace' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Access denied: path must be within /workspace")
      end
    end

    context 'with relative path that escapes workspace' do
      let(:input) { { "path" => "../../../etc/passwd", "content" => "malicious" } }

      before do
        allow(File).to receive(:join).with("/workspace", "../../../etc/passwd").and_return("/etc/passwd")
      end

      it 'returns failure for path traversal attempt' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Access denied: path must be within /workspace")
      end
    end

    context 'when file write fails' do
      let(:input) { { "path" => "test.txt", "content" => "content" } }

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write).and_raise(Errno::EACCES.new("Permission denied"))
        allow(File).to receive(:dirname).and_return("/workspace")
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Write failed: Permission denied")
      end
    end

    context 'when directory creation fails' do
      let(:input) { { "path" => "deep/nested/file.txt", "content" => "content" } }

      before do
        allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES.new("Permission denied"))
        allow(File).to receive(:dirname).and_return("/workspace/deep/nested")
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Write failed: Permission denied")
      end
    end

    context 'with large content' do
      let(:large_content) { 'x' * 100_000 }
      let(:input) { { "path" => "large.txt", "content" => large_content } }

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(File).to receive(:dirname).and_return("/workspace")
      end

      it 'handles large files' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Wrote 100000 bytes to large.txt")
        expect(File).to have_received(:write).with("/workspace/large.txt", large_content)
      end
    end

    context 'with special characters in path' do
      let(:input) { { "path" => "files/test file (copy).txt", "content" => "test" } }

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(File).to receive(:dirname).and_return("/workspace/files")
      end

      it 'handles special characters' do
        result = executor.call
        expect(result).to be_success
        expect(File).to have_received(:write).with("/workspace/files/test file (copy).txt", "test")
      end
    end
  end
end