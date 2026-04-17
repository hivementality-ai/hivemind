# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::DynamicToolSchema do
  describe ".detect_context" do
    it "detects testing from keywords" do
      expect(described_class.detect_context("run the tests")).to eq(:testing)
      expect(described_class.detect_context("add a spec for Foo")).to eq(:testing)
      expect(described_class.detect_context("rspec is failing")).to eq(:testing)
    end

    it "detects git" do
      expect(described_class.detect_context("commit this change")).to eq(:git)
      expect(described_class.detect_context("show the diff")).to eq(:git)
      expect(described_class.detect_context("push to main")).to eq(:git)
    end

    it "detects review" do
      expect(described_class.detect_context("review my PR")).to eq(:review)
    end

    it "detects rails" do
      expect(described_class.detect_context("run the migration")).to eq(:rails)
    end

    it "detects web" do
      expect(described_class.detect_context("fetch this URL")).to eq(:web)
    end

    it "returns nil when nothing matches" do
      expect(described_class.detect_context("say hello")).to be_nil
      expect(described_class.detect_context("")).to be_nil
      expect(described_class.detect_context(nil)).to be_nil
    end
  end

  describe ".filter" do
    let(:tools) do
      [
        { name: "read_file",  description: "Read a file" },
        { name: "write_file", description: "Write a file" },
        { name: "edit_file",  description: "Edit a file" },
        { name: "shell",      description: "Run a shell command" },
        { name: "glob",       description: "Glob files" },
        { name: "grep",       description: "Search in files" },
        { name: "run_specs",  description: "Execute the RSpec test suite" },
        { name: "git_diff",   description: "Show git diff" },
        { name: "web_fetch",  description: "Fetch a URL" },
        { name: "send_message", description: "Send a message to a teammate" }
      ]
    end

    it "returns all tools when context is nil" do
      expect(described_class.filter(tools, context: nil)).to eq(tools)
    end

    it "keeps base tools + context-relevant tools for :testing" do
      result = described_class.filter(tools, context: :testing)
      names = result.map { |t| t[:name] }

      expect(names).to include("read_file", "write_file", "edit_file", "shell", "grep", "glob", "run_specs")
      expect(names).not_to include("git_diff", "web_fetch", "send_message")
    end

    it "keeps git tools for :git" do
      result = described_class.filter(tools, context: :git)
      names = result.map { |t| t[:name] }

      expect(names).to include("git_diff")
      expect(names).not_to include("run_specs", "web_fetch")
    end

    it "keeps discovered tools even if they don't match the context" do
      result = described_class.filter(tools, context: :testing, discovered_names: [ "web_fetch" ])
      names = result.map { |t| t[:name] }

      expect(names).to include("web_fetch", "run_specs")
    end

    it "falls back to the full list if filtering would drop every tool" do
      only_exotic = [ { name: "send_sms", description: "Send a text message" } ]
      expect(described_class.filter(only_exotic, context: :testing)).to eq(only_exotic)
    end

    it "skips filtering when the toolset is already small" do
      tiny = tools.first(4)
      expect(described_class.filter(tiny, context: :testing)).to eq(tiny)
    end
  end
end
