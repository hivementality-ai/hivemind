# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::GlobExecutor do
  describe "#call" do
    let(:input) { { "pattern" => pattern, "path" => path } }
    let(:config) { {} }
    let(:executor) { described_class.new(input: input, config: config) }
    let(:pattern) { "*.rb" }
    let(:path) { "" }

    before do
      allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(true)
      allow(Tools::WorkspaceIo).to receive(:directory?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([ stdout, stderr, status ])
    end

    let(:stdout) { "/workspace/app/models/user.rb\n/workspace/config/routes.rb\n" }
    let(:stderr) { "" }
    let(:status) { double(success?: true) }

    context "with valid pattern" do
      it "returns matching files" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:files]).to eq([ "app/models/user.rb", "config/routes.rb" ])
        expect(result.data[:count]).to eq(2)
        expect(result.data[:output]).to include("Found 2 file(s)")
      end

      it "uses correct find command for simple patterns" do
        executor.call

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args.last).to include("find '/workspace' -name '*.rb'")
        end
      end
    end

    context "with complex pattern containing directories" do
      let(:pattern) { "**/*.js" }

      it "uses -path option for directory patterns" do
        executor.call

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args.last).to include("find '/workspace' -path '**/*.js'")
        end
      end
    end

    context "with custom path" do
      let(:path) { "/custom/path" }

      it "searches in the specified path" do
        executor.call

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args.last).to include("find '/custom/path'")
        end
      end

      it "checks if custom path exists" do
        executor.call

        expect(Tools::WorkspaceIo).to have_received(:file_exists?).with("/custom/path")
        expect(Tools::WorkspaceIo).to have_received(:directory?).with("/custom/path")
      end
    end

    context "with relative path" do
      let(:path) { "src" }

      it "converts to absolute workspace path" do
        executor.call

        expect(Tools::WorkspaceIo).to have_received(:file_exists?).with("/workspace/src")
        expect(Open3).to have_received(:capture3) do |*args|
          expect(args.last).to include("find '/workspace/src'")
        end
      end
    end

    context "with no pattern provided" do
      let(:pattern) { "" }

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to eq("No pattern provided")
      end
    end

    context "when path doesn't exist" do
      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(false)
      end

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to eq("Path not found: /workspace")
      end
    end

    context "when path is not a directory" do
      before do
        allow(Tools::WorkspaceIo).to receive(:directory?).and_return(false)
      end

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to eq("Path is not a directory: /workspace")
      end
    end

    context "when find command fails" do
      let(:status) { double(success?: false) }
      let(:stderr) { "Permission denied" }

      it "returns failure with error message" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to eq("Find command failed: Permission denied")
      end
    end

    context "when no files found" do
      let(:stdout) { "" }

      it "returns appropriate message" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:files]).to eq([])
        expect(result.data[:count]).to eq(0)
        expect(result.data[:output]).to eq("No files found matching pattern: *.rb")
      end
    end

    context "when maximum files limit is reached" do
      let(:stdout) { (1..500).map { |i| "/workspace/file#{i}.rb" }.join("\n") + "\n" }

      it "includes limit message in output" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:count]).to eq(500)
        expect(result.data[:output]).to include("Found 500 file(s) (limited to 500)")
      end
    end

    context "when executor encounters an exception" do
      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_raise(StandardError, "Docker error")
      end

      it "returns failure with error message" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to eq("Glob search failed: Docker error")
      end
    end
  end
end
