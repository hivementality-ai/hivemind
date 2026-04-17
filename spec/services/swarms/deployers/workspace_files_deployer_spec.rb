# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::WorkspaceFilesDeployer do
  let(:workspace_root) { described_class::WORKSPACE_ROOT }

  def build_document(workspace_files: [])
    Swarms::SwarmDocument.new(
      swarm_version:   "1.0",
      name:            "Test Swarm",
      workspace_files: workspace_files
    )
  end

  def encoded(content)
    Base64.strict_encode64(content)
  end

  after do
    # Clean up any files written during tests
    FileUtils.rm_f(File.join(workspace_root, "swarm_test_deploy.txt"))
    FileUtils.rm_f(File.join(workspace_root, "swarm_test_plain.txt"))
    FileUtils.rm_rf(File.join(workspace_root, "swarm_test_subdir"))
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "returns success when document has no workspace files" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "returns an empty array when no files present" do
      result = described_class.call(document: build_document)
      expect(result.payload[:workspace_files]).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Writing files
  # ---------------------------------------------------------------------------

  describe "writing files" do
    it "writes a base64-encoded file to the workspace" do
      doc    = build_document(workspace_files: [{
        "path"     => "swarm_test_deploy.txt",
        "content"  => encoded("hello from swarm"),
        "encoding" => "base64"
      }])
      result = described_class.call(document: doc)

      expect(result).to be_success
      expect(result.payload[:workspace_files].first.action).to eq(:written)
      expect(File.read(File.join(workspace_root, "swarm_test_deploy.txt"))).to eq("hello from swarm")
    end

    it "writes a plain-encoded file" do
      doc = build_document(workspace_files: [{
        "path"     => "swarm_test_plain.txt",
        "content"  => "plain content here",
        "encoding" => "plain"
      }])
      described_class.call(document: doc)
      expect(File.read(File.join(workspace_root, "swarm_test_plain.txt"))).to eq("plain content here")
    end

    it "creates parent directories as needed" do
      doc = build_document(workspace_files: [{
        "path"     => "swarm_test_subdir/nested.txt",
        "content"  => encoded("nested"),
        "encoding" => "base64"
      }])
      described_class.call(document: doc)
      expect(File.exist?(File.join(workspace_root, "swarm_test_subdir/nested.txt"))).to be true
    end

    it "overwrites an existing file" do
      path = File.join(workspace_root, "swarm_test_deploy.txt")
      File.write(path, "original")

      doc = build_document(workspace_files: [{
        "path"     => "swarm_test_deploy.txt",
        "content"  => encoded("replaced"),
        "encoding" => "base64"
      }])
      described_class.call(document: doc)
      expect(File.read(path)).to eq("replaced")
    end

    it "defaults to base64 when encoding is absent" do
      doc = build_document(workspace_files: [{
        "path"    => "swarm_test_deploy.txt",
        "content" => encoded("default encoding")
      }])
      described_class.call(document: doc)
      expect(File.read(File.join(workspace_root, "swarm_test_deploy.txt"))).to eq("default encoding")
    end
  end

  # ---------------------------------------------------------------------------
  # Unsafe paths — skipped
  # ---------------------------------------------------------------------------

  describe "unsafe path handling" do
    it "skips path traversal attempts" do
      doc    = build_document(workspace_files: [{
        "path"    => "../etc/evil.txt",
        "content" => encoded("bad")
      }])
      result = described_class.call(document: doc)
      expect(result).to be_success
      expect(result.payload[:workspace_files].first.action).to eq(:skipped)
      expect(File.exist?("/etc/evil.txt")).to be false
    end

    it "skips absolute paths" do
      doc    = build_document(workspace_files: [{
        "path"    => "/tmp/evil.txt",
        "content" => encoded("bad")
      }])
      result = described_class.call(document: doc)
      expect(result.payload[:workspace_files].first.action).to eq(:skipped)
    end

    it "still writes safe files when some entries are unsafe" do
      doc = build_document(workspace_files: [
        { "path" => "../bad.txt",              "content" => encoded("bad") },
        { "path" => "swarm_test_deploy.txt",   "content" => encoded("good"), "encoding" => "base64" }
      ])
      result  = described_class.call(document: doc)
      actions = result.payload[:workspace_files].map(&:action)

      expect(actions).to eq([:skipped, :written])
    end
  end
end
