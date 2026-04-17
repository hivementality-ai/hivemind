# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::OutputCompressor do
  describe ".compress" do
    it "returns empty input unchanged" do
      expect(described_class.compress("shell", "")).to eq("")
      expect(described_class.compress("shell", nil)).to be_nil
    end

    it "returns small outputs unchanged" do
      small = "hello\nworld\n"
      expect(described_class.compress("shell", small)).to eq(small)
    end

    context "head_tail strategy (shell)" do
      it "keeps head and tail with an omission marker" do
        big = (1..500).map { |i| "line #{i}\n" }.join
        result = described_class.compress("shell", big)

        expect(result.length).to be < big.length
        expect(result).to include("line 1\n")
        expect(result).to include("line 500\n")
        expect(result).to include("lines omitted")
      end
    end

    context "spec_summary strategy (run_specs)" do
      it "returns just the summary line on a green run" do
        output = <<~SPEC
          ...........
          Finished in 2.3 seconds (files took 1 second to load)
          12 examples, 0 failures
        SPEC

        result = described_class.compress("run_specs", output * 200)

        expect(result).to eq("12 examples, 0 failures")
      end
    end

    context "top_matches strategy (grep)" do
      it "trims to a line-bounded head with omission marker" do
        big = (1..500).map { |i| "app/file#{i}.rb:12: match\n" }.join
        result = described_class.compress("grep", big)

        expect(result).to include("more matches omitted")
        expect(result.length).to be < big.length
      end
    end

    context "tree strategy (glob)" do
      it "collapses paths into directory counts" do
        paths = Array.new(200) { |i| "app/controllers/admin/thing#{i}_controller.rb\n" }.join
        result = described_class.compress("glob", paths)

        expect(result).to include("app/controllers/admin/ (200 files)")
      end
    end

    context "unknown tool name" do
      it "uses default head_tail threshold" do
        big = (1..2000).map { |i| "line #{i}\n" }.join
        result = described_class.compress("some_custom_tool", big)

        expect(result.length).to be < big.length
      end
    end
  end
end
