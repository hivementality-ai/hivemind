# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::LoopDetector do
  describe ".analyze" do
    let(:default_config) do
      {
        history_size: 30,
        warning_threshold: 10,
        critical_threshold: 20,
        circuit_breaker_threshold: 50,
        detectors: {
          generic_repeat: true,
          ping_pong: true,
          no_progress: true
        }
      }
    end

    let(:tool_history) { [] }

    subject { described_class.analyze(tool_history: tool_history, config: default_config) }

    context "with empty history" do
      it "returns :ok" do
        expect(subject).to eq(:ok)
      end
    end

    context "with diverse tool calls" do
      let(:tool_history) do
        [
          { tool_name: "search", params: { query: "cats" }, output: "Results about cats", success: true },
          { tool_name: "read_file", params: { path: "/tmp/test" }, output: "File content here", success: true },
          { tool_name: "write_file", params: { path: "/tmp/output", content: "data" }, output: "File written successfully", success: true }
        ]
      end

      it "returns :ok for legitimate diverse tool calls" do
        expect(subject).to eq(:ok)
      end
    end

    describe "circuit breaker" do
      let(:tool_history) do
        Array.new(50) do |i|
          { tool_name: "test", params: { id: i }, output: "result #{i} with unique content to avoid similarity", success: true }
        end
      end

      it "triggers circuit breaker at threshold" do
        expect(subject).to eq(:circuit_breaker)
      end

      context "with custom threshold" do
        let(:config) { default_config.merge(circuit_breaker_threshold: 25) }
        let(:tool_history) do
          Array.new(25) do |i|
            { tool_name: "test", params: { id: i }, output: "unique result number #{i} that is totally different", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: config) }

        it "respects custom threshold" do
          expect(subject).to eq(:circuit_breaker)
        end
      end
    end

    describe "generic repeat detection" do
      # Use only generic_repeat detector to isolate behavior
      let(:isolated_config) do
        default_config.merge(detectors: { generic_repeat: true, ping_pong: false, no_progress: false })
      end

      context "at warning threshold" do
        let(:tool_history) do
          Array.new(10) do |i|
            { tool_name: "search", params: { query: "same query" }, output: "results #{i}", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "returns :warning" do
          expect(subject).to eq(:warning)
        end
      end

      context "at critical threshold" do
        let(:tool_history) do
          Array.new(20) do
            { tool_name: "search", params: { query: "same query" }, output: "same results", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "returns :critical" do
          expect(subject).to eq(:critical)
        end
      end

      context "with different parameters" do
        let(:tool_history) do
          Array.new(15) do |i|
            { tool_name: "search", params: { query: "query #{i}" }, output: "results #{i}", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "returns :ok for different parameters" do
          expect(subject).to eq(:ok)
        end
      end

      context "when detector is disabled" do
        let(:config) { default_config.merge(detectors: { generic_repeat: false, ping_pong: false, no_progress: false }) }
        let(:tool_history) do
          Array.new(25) do
            { tool_name: "search", params: { query: "same query" }, output: "same results", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: config) }

        it "returns :ok when all detectors disabled" do
          expect(subject).to eq(:ok)
        end
      end
    end

    describe "ping-pong detection" do
      # Isolate ping-pong detector
      let(:isolated_config) do
        default_config.merge(detectors: { generic_repeat: false, ping_pong: true, no_progress: false })
      end

      context "with ping-pong pattern at warning level" do
        let(:tool_history) do
          Array.new(6) do |i|
            if i.even?
              { tool_name: "search", params: { query: "cats" }, output: "cat results #{i}", success: true }
            else
              { tool_name: "read_file", params: { path: "/cats.txt" }, output: "cat file content #{i}", success: true }
            end
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "returns :warning for ping-pong pattern" do
          expect(subject).to eq(:warning)
        end
      end

      context "with ping-pong pattern at critical level" do
        let(:tool_history) do
          Array.new(10) do |i|
            if i.even?
              { tool_name: "search", params: { query: "dogs" }, output: "dog results #{i}", success: true }
            else
              { tool_name: "write_file", params: { path: "/dogs.txt", content: "dogs" }, output: "file written #{i}", success: true }
            end
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "returns :critical for extended ping-pong" do
          expect(subject).to eq(:critical)
        end
      end

      context "with same tool name (not ping-pong)" do
        let(:tool_history) do
          Array.new(8) do |i|
            { tool_name: "search", params: { query: "same" }, output: "results #{i}", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "does not trigger ping-pong for same tool" do
          expect(subject).to eq(:ok)
        end
      end

      context "when detector is disabled" do
        let(:config) { default_config.merge(detectors: { generic_repeat: false, ping_pong: false, no_progress: false }) }
        let(:tool_history) do
          Array.new(12) do |i|
            if i.even?
              { tool_name: "tool_a", params: {}, output: "result a #{i}", success: true }
            else
              { tool_name: "tool_b", params: {}, output: "result b #{i}", success: true }
            end
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: config) }

        it "returns :ok when disabled" do
          expect(subject).to eq(:ok)
        end
      end
    end

    describe "no-progress detection" do
      # Isolate no-progress detector
      let(:isolated_config) do
        default_config.merge(detectors: { generic_repeat: false, ping_pong: false, no_progress: true })
      end

      context "with identical outputs at warning level" do
        let(:tool_history) do
          Array.new(5) do |i|
            { tool_name: "analyze_#{i}", params: { data: "different_#{i}" }, output: "identical output", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "returns :warning for identical outputs" do
          expect(subject).to eq(:warning)
        end
      end

      context "with identical outputs at critical level" do
        let(:tool_history) do
          Array.new(10) do |i|
            { tool_name: "process_#{i}", params: { id: i }, output: "same result every time", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "returns :critical for many identical outputs" do
          expect(subject).to eq(:critical)
        end
      end

      context "with different content" do
        let(:tool_history) do
          Array.new(6) do |i|
            { tool_name: "task_#{i}", params: {}, output: "completely unique output number #{i} with very different words #{('a'..'z').to_a.sample(10).join}", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "returns :ok for different content" do
          expect(subject).to eq(:ok)
        end
      end

      context "when detector is disabled" do
        let(:config) { default_config.merge(detectors: { generic_repeat: false, ping_pong: false, no_progress: false }) }
        let(:tool_history) do
          Array.new(15) do |i|
            { tool_name: "task_#{i}", params: { id: i }, output: "identical output", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: config) }

        it "returns :ok when disabled" do
          expect(subject).to eq(:ok)
        end
      end
    end

    describe "configurable thresholds" do
      let(:custom_config) do
        {
          history_size: 15,
          warning_threshold: 5,
          critical_threshold: 8,
          circuit_breaker_threshold: 20,
          detectors: {
            generic_repeat: true,
            ping_pong: false,
            no_progress: false
          }
        }
      end

      context "with custom warning threshold" do
        let(:tool_history) do
          Array.new(5) do |i|
            { tool_name: "test", params: { same: true }, output: "different output #{i}", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: custom_config) }

        it "respects custom thresholds" do
          expect(subject).to eq(:warning)
        end
      end

      context "below custom warning threshold" do
        let(:tool_history) do
          Array.new(4) do |i|
            { tool_name: "test", params: { same: true }, output: "output #{i}", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: custom_config) }

        it "does not trigger warning below threshold" do
          expect(subject).to eq(:ok)
        end
      end

      context "with custom critical threshold" do
        let(:tool_history) do
          Array.new(8) do
            { tool_name: "test", params: { same: true }, output: "same", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: custom_config) }

        it "respects custom critical threshold" do
          expect(subject).to eq(:critical)
        end
      end
    end

    describe "mixed scenarios" do
      context "with both repeat and ping-pong patterns" do
        let(:tool_history) do
          repeat_calls = Array.new(10) do |i|
            { tool_name: "repeat_tool", params: { same: true }, output: "repeated #{i}", success: true }
          end

          ping_pong_calls = Array.new(4) do |i|
            if i.even?
              { tool_name: "ping", params: {}, output: "ping result #{i}", success: true }
            else
              { tool_name: "pong", params: {}, output: "pong result #{i}", success: true }
            end
          end

          repeat_calls + ping_pong_calls
        end

        it "detects the most severe condition" do
          expect(subject).to eq(:warning)
        end
      end

      context "with history size limit" do
        let(:config) { default_config.merge(history_size: 5, detectors: { generic_repeat: true, ping_pong: false, no_progress: false }) }
        let(:tool_history) do
          old_calls = Array.new(10) do |i|
            { tool_name: "old_tool", params: { id: i }, output: "old result #{i}", success: true }
          end

          recent_calls = Array.new(3) do |i|
            { tool_name: "recent_tool", params: { same: true }, output: "recent #{i}", success: true }
          end

          old_calls + recent_calls
        end

        subject { described_class.analyze(tool_history: tool_history, config: config) }

        it "only considers recent history" do
          expect(subject).to eq(:ok)
        end
      end

      context "with all detectors disabled" do
        let(:config) { default_config.merge(detectors: { generic_repeat: false, ping_pong: false, no_progress: false }) }
        let(:tool_history) do
          Array.new(30) do
            { tool_name: "same", params: {}, output: "same output", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: config) }

        it "returns :ok when all detectors disabled" do
          expect(subject).to eq(:ok)
        end
      end
    end

    describe "edge cases" do
      context "with minimal tool history" do
        let(:tool_history) do
          [
            { tool_name: "single", params: {}, output: "result", success: true }
          ]
        end

        it "handles single tool call gracefully" do
          expect(subject).to eq(:ok)
        end
      end

      context "with nil outputs" do
        # 8 identical calls with nil output → generic_repeat catches at warning (8 < 10), but
        # no_progress also triggers. Use isolated config to test nil safety.
        let(:tool_history) do
          Array.new(8) do
            { tool_name: "test", params: {}, output: nil, success: false }
          end
        end

        it "handles nil outputs without errors" do
          expect { subject }.not_to raise_error
        end
      end

      context "with empty string outputs" do
        let(:isolated_config) do
          default_config.merge(detectors: { generic_repeat: true, ping_pong: false, no_progress: false })
        end
        let(:tool_history) do
          Array.new(12) do
            { tool_name: "test", params: {}, output: "", success: true }
          end
        end

        subject { described_class.analyze(tool_history: tool_history, config: isolated_config) }

        it "detects repeated empty output calls" do
          expect(subject).to eq(:warning)
        end
      end
    end
  end
end
