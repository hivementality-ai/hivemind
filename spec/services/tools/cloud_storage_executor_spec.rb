# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::CloudStorageExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    allow(CloudStorage::ConfigureRemote).to receive(:list_remotes).and_return(['drive', 's3bucket'])
    allow(FileUtils).to receive(:mkdir_p)
    allow(File).to receive(:basename).and_call_original
    allow(File).to receive(:dirname).and_call_original
  end

  describe '#call' do
    context 'with remotes action' do
      let(:input) { { "action" => "remotes" } }

      it 'returns list of configured remotes' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("☁️  drive")
        expect(result.data[:output]).to include("☁️  s3bucket")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'when no remotes configured' do
        before do
          allow(CloudStorage::ConfigureRemote).to receive(:list_remotes).and_return([])
        end

        it 'returns helpful message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("No remotes configured")
          expect(result.data[:output]).to include("/integrations")
        end
      end
    end

    context 'with list action' do
      let(:input) { { "action" => "list", "path" => "documents" } }

      before do
        mock_rclone_response('lsjson', [
          { "Path" => "file1.txt", "Size" => 1024, "IsDir" => false },
          { "Path" => "folder1", "Size" => 0, "IsDir" => true }
        ])
      end

      it 'returns file listing' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("📄 file1.txt (1.0 KB)")
        expect(result.data[:output]).to include("📁 folder1")
        expect(result.data[:output]).to include("drive:/documents")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls rclone with correct arguments' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          { "RCLONE_CONFIG" => anything },
          "rclone", "lsjson", "drive:documents", "--no-modtime"
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

      context 'when directory is empty' do
        before do
          mock_rclone_response('lsjson', [])
        end

        it 'returns empty directory message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("No files in drive:/documents")
        end
      end
    end

    context 'with search action' do
      let(:input) { { "action" => "search", "query" => "report", "path" => "documents" } }

      before do
        mock_rclone_response('lsjson', [
          { "Path" => "annual_report.pdf", "Size" => 5242880, "IsDir" => false },
          { "Path" => "photo.jpg", "Size" => 1048576, "IsDir" => false },
          { "Path" => "monthly_report.docx", "Size" => 2097152, "IsDir" => false }
        ])
      end

      it 'returns matching files' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("📄 annual_report.pdf")
        expect(result.data[:output]).to include("📄 monthly_report.docx")
        expect(result.data[:output]).not_to include("photo.jpg")
        expect(result.data[:output]).to include("Found 2 files matching 'report'")
      end

      context 'without query' do
        let(:input) { { "action" => "search", "path" => "documents" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No query provided")
        end
      end

      context 'when no matches found' do
        before do
          mock_rclone_response('lsjson', [
            { "Path" => "photo.jpg", "Size" => 1048576, "IsDir" => false }
          ])
        end

        it 'returns no matches message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("No files matching 'report'")
        end
      end
    end

    context 'with read action' do
      let(:input) { { "action" => "read", "path" => "document.txt" } }

      before do
        mock_rclone_command('cat', "This is the file content\nSecond line")
      end

      it 'returns file content' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("drive:document.txt")
        expect(result.data[:output]).to include("This is the file content")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls rclone cat with head limit' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          { "RCLONE_CONFIG" => anything },
          "rclone", "cat", "drive:document.txt", "--head", "30000"
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
    end

    context 'with download action' do
      let(:input) { { "action" => "download", "path" => "file.pdf", "dest" => "/workspace/downloads/" } }

      before do
        mock_rclone_command('copy', "")
      end

      it 'downloads file successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Downloaded drive:file.pdf → /workspace/downloads/")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'creates destination directory' do
        executor.call
        expect(FileUtils).to have_received(:mkdir_p).with("/workspace/downloads/")
      end

      context 'without destination' do
        let(:input) { { "action" => "download", "path" => "file.pdf" } }

        it 'uses default destination' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("→ /workspace/downloads/")
        end
      end
    end

    context 'with upload action' do
      let(:input) { { "action" => "upload", "local_path" => "/workspace/test.txt", "dest" => "uploads/" } }

      before do
        mock_rclone_command('copy', "")
        allow(File).to receive(:basename).with("/workspace/test.txt").and_return("test.txt")
      end

      it 'uploads file successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Uploaded test.txt → drive:/uploads/")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'without local_path' do
        let(:input) { { "action" => "upload", "dest" => "uploads/" } }

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
        expect(result.data[:output]).to eq("Created directory: drive:new_folder")
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
        expect(result.data[:output]).to eq("Deleted: drive:old_file.txt")
        expect(result.data[:exit_code]).to eq(0)
      end
    end

    context 'with info action' do
      let(:input) { { "action" => "info", "path" => "documents/file.txt" } }

      before do
        allow(File).to receive(:dirname).with("documents/file.txt").and_return("documents")
        allow(File).to receive(:basename).with("documents/file.txt").and_return("file.txt")
        mock_rclone_response('lsjson', [
          {
            "Path" => "file.txt",
            "Size" => 2048,
            "IsDir" => false,
            "ModTime" => "2023-01-15T10:30:00Z",
            "MimeType" => "text/plain"
          }
        ])
      end

      it 'returns file information' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Name: file.txt")
        expect(result.data[:output]).to include("Type: File")
        expect(result.data[:output]).to include("Size: 2.0 KB")
        expect(result.data[:output]).to include("Modified: 2023-01-15T10:30:00Z")
        expect(result.data[:output]).to include("MimeType: text/plain")
      end

      context 'when file not found' do
        before do
          mock_rclone_response('lsjson', [])
        end

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Not found: documents/file.txt")
        end
      end
    end

    context 'with about action' do
      let(:input) { { "action" => "about" } }

      before do
        mock_rclone_response('about', {
          "total" => 16106127360,
          "used" => 8053063680,
          "free" => 8053063680,
          "trashed" => 0
        }, json: true)
      end

      it 'returns remote information' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Remote: drive")
        expect(result.data[:output]).to include("Total: 15.0 GB")
        expect(result.data[:output]).to include("Used: 7.5 GB")
        expect(result.data[:output]).to include("Free: 7.5 GB")
      end
    end

    context 'with custom remote specified' do
      let(:input) { { "action" => "list", "remote" => "s3bucket", "path" => "files" } }

      before do
        mock_rclone_response('lsjson', [])
      end

      it 'uses specified remote' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          anything, "rclone", "lsjson", "s3bucket:files", "--no-modtime"
        )
      end
    end

    context 'when no remotes are configured' do
      let(:input) { { "action" => "list" } }

      before do
        allow(CloudStorage::ConfigureRemote).to receive(:list_remotes).and_return([])
      end

      it 'returns failure for actions requiring remote' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("No cloud storage remotes configured")
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

      it 'returns rclone not installed error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("rclone not installed")
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("remotes, list, search")
      end
    end

    context 'when operation times out' do
      let(:input) { { "action" => "list" } }

      before do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      end

      it 'returns timeout error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Cloud storage error")
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

  private

  def mock_rclone_response(command, response_data, json: false)
    stdout = json ? JSON.generate(response_data) : JSON.generate(response_data)
    allow(Open3).to receive(:capture3).with(
      hash_including("RCLONE_CONFIG"),
      "rclone", command, anything, *anything
    ).and_return([stdout, '', double(success?: true)])
  end

  def mock_rclone_command(command, stdout)
    allow(Open3).to receive(:capture3).with(
      hash_including("RCLONE_CONFIG"),
      "rclone", command, *anything
    ).and_return([stdout, '', double(success?: true)])
  end
end