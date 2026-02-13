# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::DriveExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    allow(FileUtils).to receive(:mkdir_p)
    allow(File).to receive(:basename).and_call_original
    allow(File).to receive(:dirname).and_call_original
  end

  describe '#call' do
    context 'with list action' do
      let(:input) { { "action" => "list", "path" => "documents" } }

      before do
        mock_rclone_response('lsjson', [
          { "Path" => "report.pdf", "Size" => 1048576, "IsDir" => false, "ModTime" => "2023-01-01T10:00:00Z" },
          { "Path" => "images", "Size" => 0, "IsDir" => true }
        ])
      end

      it 'lists files successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Files in /documents:")
        expect(result.data[:output]).to include("📄 report.pdf (1.0 MB)")
        expect(result.data[:output]).to include("📁 images")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls rclone with correct parameters' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything, "rclone", "lsjson", "gdrive:documents", "--no-modtime", timeout: 30
        )
      end

      context 'with custom limit' do
        let(:input) { { "action" => "list", "path" => "documents", "limit" => 5 } }

        before do
          files = (1..10).map { |i| { "Path" => "file#{i}.txt", "Size" => 1024, "IsDir" => false } }
          mock_rclone_response('lsjson', files)
        end

        it 'respects limit parameter' do
          result = executor.call
          lines = result.data[:output].lines.select { |line| line.include?('📄') }
          expect(lines.size).to eq(5)
        end
      end

      context 'without path' do
        let(:input) { { "action" => "list" } }

        before do
          mock_rclone_response('lsjson', [])
        end

        it 'lists root directory' do
          executor.call
          expect(Open3).to have_received(:capture3).with(
            anything, "rclone", "lsjson", "gdrive:", "--no-modtime", timeout: 30
          )
        end
      end

      context 'when directory is empty' do
        before do
          mock_rclone_response('lsjson', [])
        end

        it 'shows empty directory message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("No files in /documents")
        end
      end
    end

    context 'with search action' do
      let(:input) { { "action" => "search", "query" => "invoice" } }

      before do
        mock_rclone_response('lsjson', [
          { "Path" => "invoices/2023/invoice_001.pdf", "Size" => 524288, "IsDir" => false },
          { "Path" => "documents/report.pdf", "Size" => 1048576, "IsDir" => false },
          { "Path" => "invoices/2023/invoice_002.pdf", "Size" => 612844, "IsDir" => false }
        ])
      end

      it 'searches files successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Found 2 files matching 'invoice':")
        expect(result.data[:output]).to include("📄 invoices/2023/invoice_001.pdf")
        expect(result.data[:output]).to include("📄 invoices/2023/invoice_002.pdf")
        expect(result.data[:output]).not_to include("report.pdf")
      end

      it 'calls rclone with recursive and files-only flags' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything, "rclone", "lsjson", "gdrive:", "--recursive", "--no-modtime", "--files-only", timeout: 30
        )
      end

      context 'without query' do
        let(:input) { { "action" => "search" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No query provided")
        end
      end

      context 'with no matches' do
        before do
          mock_rclone_response('lsjson', [
            { "Path" => "documents/report.pdf", "Size" => 1048576, "IsDir" => false }
          ])
        end

        it 'shows no matches message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("No files matching 'invoice'")
        end
      end
    end

    context 'with read action' do
      let(:input) { { "action" => "read", "path" => "document.txt" } }

      before do
        mock_rclone_command('cat', "This is the file content.\nSecond line of content.")
      end

      it 'reads file successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Content of document.txt:")
        expect(result.data[:output]).to include("This is the file content.")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls rclone cat' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything, "rclone", "cat", "gdrive:document.txt", timeout: 30
        )
      end

      context 'without path' do
        let(:input) { { "action" => "read" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No path provided")
        end
      end

      context 'with large file content' do
        let(:large_content) { 'x' * 35_000 }

        before do
          mock_rclone_command('cat', large_content)
        end

        it 'truncates content to 30KB' do
          result = executor.call
          expect(result).to be_success
          content_part = result.data[:output].split("\n\n").last
          expect(content_part.length).to be <= 30_000
        end
      end
    end

    context 'with download action' do
      let(:input) { { "action" => "download", "path" => "report.pdf", "dest" => "/workspace/downloads/" } }

      before do
        mock_rclone_command('copy', "")
        allow(File).to receive(:basename).with("report.pdf").and_return("report.pdf")
      end

      it 'downloads file successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Downloaded report.pdf → /workspace/downloads/report.pdf")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'creates destination directory' do
        executor.call
        expect(FileUtils).to have_received(:mkdir_p).with("/workspace/downloads/")
      end

      context 'without destination' do
        let(:input) { { "action" => "download", "path" => "report.pdf" } }

        it 'uses default destination' do
          result = executor.call
          expect(result.data[:output]).to include("→ /workspace/downloads/report.pdf")
        end
      end

      context 'without path' do
        let(:input) { { "action" => "download" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No path provided")
        end
      end
    end

    context 'with upload action' do
      let(:input) { { "action" => "upload", "local_path" => "/workspace/file.txt", "dest" => "documents/" } }

      before do
        mock_rclone_command('copy', "")
        allow(File).to receive(:basename).with("/workspace/file.txt").and_return("file.txt")
      end

      it 'uploads file successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Uploaded file.txt → Drive:/documents/")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls rclone copy with correct parameters' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything, "rclone", "copy", "/workspace/file.txt", "gdrive:documents/", timeout: 30
        )
      end

      context 'without destination' do
        let(:input) { { "action" => "upload", "local_path" => "/workspace/file.txt" } }

        it 'uploads to root' do
          result = executor.call
          expect(result.data[:output]).to eq("Uploaded file.txt → Drive:/")
        end
      end

      context 'without local_path' do
        let(:input) { { "action" => "upload" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No local_path provided")
        end
      end
    end

    context 'with mkdir action' do
      let(:input) { { "action" => "mkdir", "path" => "new_folder" } }

      before do
        mock_rclone_command('mkdir', "")
      end

      it 'creates directory successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Created directory: new_folder")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'without path' do
        let(:input) { { "action" => "mkdir" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No path provided")
        end
      end
    end

    context 'with delete action' do
      let(:input) { { "action" => "delete", "path" => "old_file.txt" } }

      before do
        mock_rclone_command('delete', "")
      end

      it 'deletes file successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Deleted: old_file.txt")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'without path' do
        let(:input) { { "action" => "delete" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No path provided")
        end
      end
    end

    context 'with info action' do
      let(:input) { { "action" => "info", "path" => "documents/report.pdf" } }

      before do
        allow(File).to receive(:dirname).with("documents/report.pdf").and_return("documents")
        allow(File).to receive(:basename).with("documents/report.pdf").and_return("report.pdf")
        mock_rclone_response('lsjson', [
          {
            "Path" => "report.pdf",
            "Size" => 2097152,
            "IsDir" => false,
            "ModTime" => "2023-01-15T10:30:00Z",
            "MimeType" => "application/pdf",
            "ID" => "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"
          }
        ])
      end

      it 'returns file information' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Name: report.pdf")
        expect(result.data[:output]).to include("Type: File")
        expect(result.data[:output]).to include("Size: 2.0 MB")
        expect(result.data[:output]).to include("Modified: 2023-01-15T10:30:00Z")
        expect(result.data[:output]).to include("MimeType: application/pdf")
        expect(result.data[:output]).to include("ID: 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms")
      end

      context 'when file not found' do
        before do
          mock_rclone_response('lsjson', [])
        end

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("File not found: documents/report.pdf")
        end
      end

      context 'for directory' do
        before do
          mock_rclone_response('lsjson', [
            { "Path" => "folder", "Size" => 0, "IsDir" => true, "ModTime" => "2023-01-15T10:30:00Z" }
          ])
        end

        let(:input) { { "action" => "info", "path" => "documents/folder" } }

        it 'shows directory info without size' do
          result = executor.call
          expect(result.data[:output]).to include("Type: Directory")
          expect(result.data[:output]).not_to include("Size:")
        end
      end
    end

    context 'with status action' do
      let(:input) { { "action" => "status" } }

      before do
        mock_rclone_command('about', "Total: 15 GiB\nUsed: 7.5 GiB\nFree: 7.5 GiB")
      end

      it 'shows drive status' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Drive connected:")
        expect(result.data[:output]).to include("Total: 15 GiB")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'when drive is not configured' do
        before do
          allow(Open3).to receive(:capture3).and_return(['', 'config not found', double(success?: false)])
        end

        it 'returns failure with setup instructions' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to include("Drive not configured")
          expect(result.error).to include("rclone config")
        end
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("list, search, read, download, upload")
      end
    end

    context 'when rclone command fails' do
      let(:input) { { "action" => "list", "path" => "invalid" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['', 'directory not found', double(success?: false)])
      end

      it 'returns rclone error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("rclone: directory not found")
      end
    end

    context 'when rclone is not installed' do
      let(:input) { { "action" => "list" } }

      before do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
      end

      it 'returns installation message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("rclone not installed")
        expect(result.error).to include("https://rclone.org/install/")
      end
    end

    context 'with custom remote name' do
      let(:input) { { "action" => "list" } }

      before do
        create(:vault_entry, namespace: 'google', key: 'drive_remote', value: 'mydrive')
        mock_rclone_response('lsjson', [])
      end

      it 'uses custom remote name' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything, "rclone", "lsjson", "mydrive:", "--no-modtime", timeout: 30
        )
      end
    end

    context 'with custom rclone config path' do
      let(:input) { { "action" => "list" } }

      before do
        create(:vault_entry, namespace: 'google', key: 'rclone_config_path', value: '/custom/rclone.conf')
        mock_rclone_response('lsjson', [])
      end

      it 'uses custom config path' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          { "RCLONE_CONFIG" => '/custom/rclone.conf' },
          "rclone", "lsjson", "gdrive:", "--no-modtime", timeout: 30
        )
      end
    end

    context 'when JSON parsing fails' do
      let(:input) { { "action" => "list" } }

      before do
        allow(Open3).to receive(:capture3).and_return(['invalid json', '', double(success?: true)])
      end

      it 'returns failure with parsing error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Drive error:")
      end
    end
  end

  describe '#human_size' do
    it 'formats bytes correctly' do
      expect(executor.send(:human_size, 0)).to eq("0 B")
      expect(executor.send(:human_size, 1023)).to eq("1023.0 B")
      expect(executor.send(:human_size, 1024)).to eq("1.0 KB")
      expect(executor.send(:human_size, 1048576)).to eq("1.0 MB")
      expect(executor.send(:human_size, 1073741824)).to eq("1.0 GB")
      expect(executor.send(:human_size, nil)).to eq("0 B")
    end
  end

  describe '#vault_get' do
    it 'retrieves vault entries' do
      create(:vault_entry, namespace: 'google', key: 'test_key', value: 'test_value')
      result = executor.send(:vault_get, 'google', 'test_key')
      expect(result).to eq('test_value')
    end

    it 'returns nil for non-existent entries' do
      result = executor.send(:vault_get, 'nonexistent', 'key')
      expect(result).to be_nil
    end
  end

  describe '#remote' do
    it 'uses default remote name' do
      expect(executor.send(:remote)).to eq('gdrive')
    end

    it 'uses vault-configured remote name' do
      create(:vault_entry, namespace: 'google', key: 'drive_remote', value: 'custom_drive')
      executor.remove_instance_variable(:@remote) if executor.instance_variable_defined?(:@remote)
      expect(executor.send(:remote)).to eq('custom_drive')
    end
  end

  private

  def mock_rclone_response(command, response_data)
    stdout = JSON.generate(response_data)
    allow(Open3).to receive(:capture3).with(
      anything, "rclone", command, anything, *anything
    ).and_return([stdout, '', double(success?: true)])
  end

  def mock_rclone_command(command, stdout)
    allow(Open3).to receive(:capture3).with(
      anything, "rclone", command, *anything
    ).and_return([stdout, '', double(success?: true)])
  end
end