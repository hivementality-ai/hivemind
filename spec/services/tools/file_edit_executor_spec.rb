# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::FileEditExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }
  let(:workspace_path) { "/workspace" }

  before do
    allow(ENV).to receive(:fetch).with("WORKSPACE_PATH", "/workspace").and_return(workspace_path)
  end

  describe '#call' do
    context 'with valid edit parameters' do
      let(:input) { { "path" => "test.txt", "old_text" => "hello", "new_text" => "goodbye" } }
      let(:original_content) { "Say hello to the world" }
      let(:full_path) { "/workspace/test.txt" }

      before do
        allow(File).to receive(:expand_path).with("test.txt", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:read).with(full_path).and_return(original_content)
        allow(File).to receive(:write)
      end

      it 'returns success with edit summary' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Edited test.txt: replaced 1 lines with 1 lines")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'writes edited content to file' do
        executor.call
        expect(File).to have_received(:write).with(full_path, "Say goodbye to the world")
      end
    end

    context 'with multiline replacement' do
      let(:input) { { "path" => "code.rb", "old_text" => "def old_method\n  puts 'old'\nend", "new_text" => "def new_method\n  puts 'new'\n  puts 'improved'\nend" } }
      let(:original_content) { "class Test\n  def old_method\n    puts 'old'\n  end\nend" }
      let(:full_path) { "/workspace/code.rb" }

      before do
        allow(File).to receive(:expand_path).with("code.rb", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:read).with(full_path).and_return(original_content)
        allow(File).to receive(:write)
      end

      it 'handles multiline edits' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Edited code.rb: replaced 3 lines with 4 lines")
        expect(File).to have_received(:write).with(full_path, "class Test\n  def new_method\n    puts 'new'\n    puts 'improved'\n  end\nend")
      end
    end

    context 'without path parameter' do
      let(:input) { { "old_text" => "test", "new_text" => "replaced" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No path provided")
      end
    end

    context 'with empty path' do
      let(:input) { { "path" => "  ", "old_text" => "test", "new_text" => "replaced" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No path provided")
      end
    end

    context 'without old_text parameter' do
      let(:input) { { "path" => "test.txt", "new_text" => "replaced" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No old_text provided")
      end
    end

    context 'with empty old_text' do
      let(:input) { { "path" => "test.txt", "old_text" => "", "new_text" => "replaced" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No old_text provided")
      end
    end

    context 'without new_text parameter' do
      let(:input) { { "path" => "test.txt", "old_text" => "remove this" } }
      let(:original_content) { "Please remove this line" }
      let(:full_path) { "/workspace/test.txt" }

      before do
        allow(File).to receive(:expand_path).with("test.txt", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:read).with(full_path).and_return(original_content)
        allow(File).to receive(:write)
      end

      it 'replaces with empty string' do
        result = executor.call
        expect(result).to be_success
        expect(File).to have_received(:write).with(full_path, "Please  line")
      end
    end

    context 'when file does not exist' do
      let(:input) { { "path" => "missing.txt", "old_text" => "test", "new_text" => "replaced" } }
      let(:full_path) { "/workspace/missing.txt" }

      before do
        allow(File).to receive(:expand_path).with("missing.txt", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(false)
      end

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("File not found: missing.txt")
      end
    end

    context 'when old_text is not found' do
      let(:input) { { "path" => "test.txt", "old_text" => "missing", "new_text" => "replaced" } }
      let(:original_content) { "This file has different content" }
      let(:full_path) { "/workspace/test.txt" }

      before do
        allow(File).to receive(:expand_path).with("test.txt", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:read).with(full_path).and_return(original_content)
      end

      it 'returns failure with helpful message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("old_text not found in test.txt. Make sure it matches exactly (including whitespace).")
      end
    end

    context 'when old_text appears multiple times' do
      let(:input) { { "path" => "test.txt", "old_text" => "duplicate", "new_text" => "replaced" } }
      let(:original_content) { "This duplicate text has duplicate words" }
      let(:full_path) { "/workspace/test.txt" }

      before do
        allow(File).to receive(:expand_path).with("test.txt", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:read).with(full_path).and_return(original_content)
      end

      it 'returns failure for ambiguous match' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("old_text found 2 times in test.txt. Must match exactly once for safe editing.")
      end
    end

    context 'with path traversal attempt' do
      let(:input) { { "path" => "../../../etc/passwd", "old_text" => "root", "new_text" => "hacked" } }

      before do
        allow(File).to receive(:expand_path).with("../../../etc/passwd", workspace_path).and_return("/etc/passwd")
      end

      it 'prevents path traversal' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Edit failed: Path traversal denied: ../../../etc/passwd")
      end
    end

    context 'when file read fails' do
      let(:input) { { "path" => "test.txt", "old_text" => "test", "new_text" => "replaced" } }
      let(:full_path) { "/workspace/test.txt" }

      before do
        allow(File).to receive(:expand_path).with("test.txt", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:read).with(full_path).and_raise(Errno::EACCES.new("Permission denied"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Edit failed: Permission denied")
      end
    end

    context 'when file write fails' do
      let(:input) { { "path" => "test.txt", "old_text" => "hello", "new_text" => "goodbye" } }
      let(:original_content) { "Say hello to the world" }
      let(:full_path) { "/workspace/test.txt" }

      before do
        allow(File).to receive(:expand_path).with("test.txt", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:read).with(full_path).and_return(original_content)
        allow(File).to receive(:write).and_raise(Errno::EACCES.new("Permission denied"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Edit failed: Permission denied")
      end
    end

    context 'with special characters in old_text' do
      let(:input) { { "path" => "test.txt", "old_text" => "special chars: \n\t\"quotes\"", "new_text" => "replaced" } }
      let(:original_content) { "File with special chars: \n\t\"quotes\" inside" }
      let(:full_path) { "/workspace/test.txt" }

      before do
        allow(File).to receive(:expand_path).with("test.txt", workspace_path).and_return(full_path)
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:read).with(full_path).and_return(original_content)
        allow(File).to receive(:write)
      end

      it 'handles special characters correctly' do
        result = executor.call
        expect(result).to be_success
        expect(File).to have_received(:write).with(full_path, "File with replaced inside")
      end
    end
  end

  describe '#resolve_path' do
    it 'resolves relative paths within workspace' do
      path = executor.send(:resolve_path, "test.txt")
      expect(path).to eq("/workspace/test.txt")
    end

    it 'blocks path traversal attempts' do
      expect {
        executor.send(:resolve_path, "../../../etc/passwd")
      }.to raise_error("Path traversal denied: ../../../etc/passwd")
    end

    it 'uses custom workspace path from environment' do
      allow(ENV).to receive(:fetch).with("WORKSPACE_PATH", "/workspace").and_return("/custom/workspace")
      allow(File).to receive(:expand_path).with("test.txt", "/custom/workspace").and_return("/custom/workspace/test.txt")
      
      path = executor.send(:resolve_path, "test.txt")
      expect(path).to eq("/custom/workspace/test.txt")
    end
  end
end