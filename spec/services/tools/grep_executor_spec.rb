# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::GrepExecutor do
  let(:agent) { create(:agent) }
  let(:executor) { described_class.new(input: input, config: config, agent: agent) }
  let(:config) { {} }

  describe "#call" do
    context "with valid pattern" do
      let(:input) { { "pattern" => "test_pattern" } }
      let(:grep_output) do
        "/workspace/file1.txt:1:This is a test_pattern line\n" \
        "/workspace/file2.rb:15:def test_pattern_method\n" \
        "/workspace/subdir/file3.py:42:# test_pattern comment\n"
      end

      before do
        allow(Open3).to receive(:capture3).and_return([
          grep_output,
          "",
          double(success?: true, exitstatus: 0)
        ])
      end

      it "executes grep and returns structured results" do
        result = executor.call

        expect(result.success?).to be true
        expect(result.data[:results]).to be_an(Array)
        expect(result.data[:results].length).to eq(3)
        expect(result.data[:count]).to eq(3)

        first_result = result.data[:results][0]
        expect(first_result).to eq({
          file: "/workspace/file1.txt",
          line_number: 1,
          text: "This is a test_pattern line"
        })

        second_result = result.data[:results][1]
        expect(second_result).to eq({
          file: "/workspace/file2.rb",
          line_number: 15,
          text: "def test_pattern_method"
        })

        third_result = result.data[:results][2]
        expect(third_result).to eq({
          file: "/workspace/subdir/file3.py",
          line_number: 42,
          text: "# test_pattern comment"
        })
      end

      it "calls grep with correct command" do
        executor.call

        expect(Open3).to have_received(:capture3).with(
          "docker", "exec", Tools::WorkspaceIo::WORKSPACE_CONTAINER, "bash", "-c",
          "grep -rn 'test_pattern' '/workspace'"
        )
      end
    end

    context "with custom path" do
      let(:input) { { "pattern" => "test", "path" => "/workspace/subdir" } }

      before do
        allow(Open3).to receive(:capture3).and_return([
          "/workspace/subdir/file.txt:1:test line\n",
          "",
          double(success?: true, exitstatus: 0)
        ])
      end

      it "uses the specified path" do
        executor.call

        expect(Open3).to have_received(:capture3).with(
          "docker", "exec", Tools::WorkspaceIo::WORKSPACE_CONTAINER, "bash", "-c",
          "grep -rn 'test' '/workspace/subdir'"
        )
      end
    end

    context "with case insensitive option" do
      let(:input) { { "pattern" => "TEST", "case_insensitive" => true } }

      before do
        allow(Open3).to receive(:capture3).and_return([
          "/workspace/file.txt:1:test line\n",
          "",
          double(success?: true, exitstatus: 0)
        ])
      end

      it "adds -i flag to grep command" do
        executor.call

        expect(Open3).to have_received(:capture3).with(
          "docker", "exec", Tools::WorkspaceIo::WORKSPACE_CONTAINER, "bash", "-c",
          "grep -rn -i 'TEST' '/workspace'"
        )
      end
    end

    context "with max_results limit" do
      let(:input) { { "pattern" => "test", "max_results" => 2 } }
      let(:long_output) do
        "/workspace/file1.txt:1:test1\n" \
        "/workspace/file2.txt:2:test2\n" \
        "/workspace/file3.txt:3:test3\n" \
        "/workspace/file4.txt:4:test4\n"
      end

      before do
        allow(Open3).to receive(:capture3).and_return([
          long_output,
          "",
          double(success?: true, exitstatus: 0)
        ])
      end

      it "limits the number of results returned" do
        result = executor.call

        expect(result.success?).to be true
        expect(result.data[:results].length).to eq(2)
        expect(result.data[:count]).to eq(2)
      end
    end

    context "when grep finds no matches" do
      let(:input) { { "pattern" => "nonexistent" } }

      before do
        allow(Open3).to receive(:capture3).and_return([
          "",
          "",
          double(success?: false, exitstatus: 1)
        ])
      end

      it "returns empty results" do
        result = executor.call

        expect(result.success?).to be true
        expect(result.data[:results]).to eq([])
        expect(result.data[:count]).to eq(0)
      end
    end

    context "when grep command fails" do
      let(:input) { { "pattern" => "test" } }

      before do
        allow(Open3).to receive(:capture3).and_return([
          "",
          "Permission denied",
          double(success?: false, exitstatus: 2)
        ])
      end

      it "returns failure with error message" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to include("Grep command failed")
      end
    end

    context "with no pattern" do
      let(:input) { {} }

      it "returns failure with error message" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to eq("No pattern provided")
      end
    end

    context "with empty pattern" do
      let(:input) { { "pattern" => "" } }

      it "returns failure with error message" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to eq("No pattern provided")
      end
    end

    context "when an exception occurs" do
      let(:input) { { "pattern" => "test" } }

      before do
        allow(Open3).to receive(:capture3).and_raise(StandardError, "Docker not running")
      end

      it "returns failure with error message" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to include("Grep execution failed: Docker not running")
      end
    end
  end

  describe "default values" do
    it "uses correct default max_results" do
      expect(described_class::DEFAULT_MAX_RESULTS).to eq(50)
    end
  end
end
