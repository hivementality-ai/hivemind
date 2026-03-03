# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::MigrationReport do
  subject(:report) { described_class.new(workspace_path: "/tmp/test") }

  describe "#initialize" do
    it "sets defaults" do
      expect(report.workspace_path).to eq("/tmp/test")
      expect(report.agent).to be_nil
      expect(report.identity_imported).to be false
      expect(report.memories_created).to eq(0)
      expect(report.memory_files_processed).to eq(0)
      expect(report.skills_imported).to eq([])
      expect(report.skills_skipped).to eq([])
      expect(report.channels_created).to eq([])
      expect(report.sessions_created).to eq(0)
      expect(report.tools_created).to eq([])
      expect(report.warnings).to eq([])
      expect(report.markers_found).to eq([])
    end
  end

  describe "#add_warning" do
    it "appends to warnings" do
      report.add_warning("something went wrong")
      report.add_warning("another issue")
      expect(report.warnings).to eq(["something went wrong", "another issue"])
    end
  end

  describe "#success?" do
    it "returns false when identity not imported" do
      expect(report.success?).to be false
    end

    it "returns true when identity imported and no fatal warnings" do
      report.identity_imported = true
      expect(report.success?).to be true
    end

    it "returns true with non-fatal warnings" do
      report.identity_imported = true
      report.add_warning("Minor issue")
      expect(report.success?).to be true
    end

    it "returns false with fatal warnings" do
      report.identity_imported = true
      report.add_warning("FATAL: Identity import failed")
      expect(report.success?).to be false
    end
  end

  describe "#to_console" do
    it "returns a formatted string" do
      report.identity_imported = true
      report.memories_created = 5
      report.memory_files_processed = 2
      output = report.to_console

      expect(output).to include("OpenClaw Migration Report")
      expect(output).to include("/tmp/test")
      expect(output).to include("5 created")
      expect(output).to include("SUCCESS")
    end

    it "includes skipped skills" do
      report.identity_imported = true
      report.skills_skipped = [{ name: "evil", reason: "blocked" }]
      output = report.to_console

      expect(output).to include("evil")
      expect(output).to include("blocked")
    end

    it "includes warnings" do
      report.identity_imported = true
      report.add_warning("Something failed")
      output = report.to_console

      expect(output).to include("Something failed")
    end
  end

  describe "#to_markdown" do
    it "returns markdown formatted report" do
      report.identity_imported = true
      report.memories_created = 3
      output = report.to_markdown

      expect(output).to include("# OpenClaw Migration Report")
      expect(output).to include("| Memories | 3 |")
      expect(output).to include("**SUCCESS**")
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      report.identity_imported = true
      report.memories_created = 2
      report.skills_imported = [{ name: "greet" }]
      hash = report.to_h

      expect(hash[:workspace_path]).to eq("/tmp/test")
      expect(hash[:identity_imported]).to be true
      expect(hash[:memories_created]).to eq(2)
      expect(hash[:skills_imported]).to eq(["greet"])
      expect(hash[:success]).to be true
    end
  end
end
