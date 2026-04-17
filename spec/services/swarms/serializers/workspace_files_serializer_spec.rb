# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::WorkspaceFilesSerializer do
  let(:workspace_root) { described_class::WORKSPACE_ROOT }

  def with_temp_file(relative_path, content: "hello world")
    absolute = File.join(workspace_root, relative_path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, content)
    yield relative_path
  ensure
    FileUtils.rm_f(absolute)
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "returns a successful ServiceResponse when given no paths" do
      result = described_class.call(paths: [])
      expect(result).to be_success
    end

    it "returns empty workspace_files when no paths given" do
      result = described_class.call(paths: [])
      expect(result.payload[:workspace_files]).to eq([])
    end

    it "returns a skipped array" do
      result = described_class.call(paths: [])
      expect(result.payload[:skipped]).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  describe "serializing a valid file" do
    it "includes path, content, encoding, and size" do
      with_temp_file("test_export.txt", content: "data here") do |rel|
        result = described_class.call(paths: [rel])
        entry  = result.payload[:workspace_files].first

        expect(entry["path"]).to eq(rel)
        expect(entry["encoding"]).to eq("base64")
        expect(entry["size"]).to eq("data here".bytesize)
        expect(Base64.decode64(entry["content"])).to eq("data here")
      end
    end

    it "base64-encodes binary content faithfully" do
      binary = (0..255).map(&:chr).join
      with_temp_file("binary.bin", content: binary) do |rel|
        result  = described_class.call(paths: [rel])
        decoded = Base64.decode64(result.payload[:workspace_files].first["content"])
        expect(decoded).to eq(binary)
      end
    end

    it "handles multiple valid paths" do
      with_temp_file("file_a.txt", content: "aaa") do |rel_a|
        with_temp_file("file_b.txt", content: "bbb") do |rel_b|
          result = described_class.call(paths: [rel_a, rel_b])
          expect(result.payload[:workspace_files].size).to eq(2)
          expect(result.payload[:skipped]).to be_empty
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Skipping
  # ---------------------------------------------------------------------------

  describe "skipping unsafe or invalid paths" do
    it "skips path traversal attempts" do
      result = described_class.call(paths: ["../etc/passwd"])
      expect(result.payload[:workspace_files]).to be_empty
      expect(result.payload[:skipped]).to include("../etc/passwd")
    end

    it "skips absolute paths" do
      result = described_class.call(paths: ["/etc/passwd"])
      expect(result.payload[:workspace_files]).to be_empty
      expect(result.payload[:skipped]).to include("/etc/passwd")
    end

    it "skips non-existent files" do
      result = described_class.call(paths: ["does_not_exist_xyz.txt"])
      expect(result.payload[:workspace_files]).to be_empty
      expect(result.payload[:skipped]).to include("does_not_exist_xyz.txt")
    end

    it "skips directories" do
      FileUtils.mkdir_p(File.join(workspace_root, "test_dir_xyz"))
      result = described_class.call(paths: ["test_dir_xyz"])
      expect(result.payload[:workspace_files]).to be_empty
      expect(result.payload[:skipped]).to include("test_dir_xyz")
    ensure
      FileUtils.rm_rf(File.join(workspace_root, "test_dir_xyz"))
    end

    it "mixes valid and skipped paths correctly" do
      with_temp_file("good_file.txt", content: "ok") do |rel|
        result = described_class.call(paths: [rel, "../bad"])
        expect(result.payload[:workspace_files].size).to eq(1)
        expect(result.payload[:skipped]).to eq(["../bad"])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Schema compatibility
  # ---------------------------------------------------------------------------

  describe "schema compatibility" do
    it "produces output valid against SwarmSchema workspace_files section" do
      with_temp_file("schema_test.txt", content: "validate me") do |rel|
        result = described_class.call(paths: [rel])
        raw = {
          "swarm_version"   => "1.0",
          "name"            => "Test",
          "workspace_files" => result.payload[:workspace_files]
        }
        validation = Swarms::SwarmSchema.validate(raw)
        expect(validation).to be_valid, validation.errors.inspect
      end
    end
  end
end
