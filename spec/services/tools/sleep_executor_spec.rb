# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SleepExecutor, type: :service do
  let(:session) { create(:session) }
  let(:agent) { create(:agent) }
  let(:config) { { session: session } }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(Kernel).to receive(:sleep)
    allow(SessionSignal).to receive(:check).and_return(nil)
  end

  describe "#call" do
    context "with valid seconds" do
      let(:executor) { described_class.new(input: { "seconds" => 5 }, config: config, agent: agent) }

      it "waits the requested duration and returns success" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to eq("Waited 5 seconds")
        expect(result.data[:exit_code]).to eq(0)
      end

      it "sleeps in 1-second increments" do
        executor.call

        expect(Kernel).to have_received(:sleep).with(1).exactly(5).times
      end

      it "broadcasts agent_sleeping to the session channel" do
        executor.call

        expect(ActionCable.server).to have_received(:broadcast).with(
          "session_#{session.id}",
          hash_including(
            type: "agent_sleeping",
            seconds: 5,
            timestamp: anything
          )
        )
      end

      it "checks for session signals on each poll" do
        executor.call

        expect(SessionSignal).to have_received(:check).with(session.id).exactly(5).times
      end
    end

    context "with reason" do
      let(:executor) { described_class.new(input: { "seconds" => 3, "reason" => "waiting for deploy" }, config: config, agent: agent) }

      it "includes reason in output" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to eq("Waited 3 seconds (waiting for deploy)")
      end

      it "broadcasts reason to the session channel" do
        executor.call

        expect(ActionCable.server).to have_received(:broadcast).with(
          "session_#{session.id}",
          hash_including(reason: "waiting for deploy")
        )
      end
    end

    context "with 1 second" do
      let(:executor) { described_class.new(input: { "seconds" => 1 }, config: config, agent: agent) }

      it "uses singular form in output" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to eq("Waited 1 second")
      end
    end

    context "with string seconds" do
      let(:executor) { described_class.new(input: { "seconds" => "10" }, config: config, agent: agent) }

      it "parses string input" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to eq("Waited 10 seconds")
      end
    end

    context "with maximum seconds (180)" do
      let(:executor) { described_class.new(input: { "seconds" => 180 }, config: config, agent: agent) }

      it "allows the maximum value" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to eq("Waited 180 seconds")
      end
    end

    # ── Validation ──────────────────────────────────────────────

    context "when seconds exceeds maximum" do
      let(:executor) { described_class.new(input: { "seconds" => 200 }, config: config, agent: agent) }

      it "returns failure" do
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("seconds must be between 1 and 180")
      end
    end

    context "when seconds is zero" do
      let(:executor) { described_class.new(input: { "seconds" => 0 }, config: config, agent: agent) }

      it "returns failure" do
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("seconds must be between 1 and 180")
      end
    end

    context "when seconds is negative" do
      let(:executor) { described_class.new(input: { "seconds" => -5 }, config: config, agent: agent) }

      it "returns failure" do
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("seconds must be between 1 and 180")
      end
    end

    context "when seconds is not a number" do
      let(:executor) { described_class.new(input: { "seconds" => "abc" }, config: config, agent: agent) }

      it "returns failure" do
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("seconds must be between 1 and 180")
      end
    end

    context "when seconds is nil" do
      let(:executor) { described_class.new(input: { "seconds" => nil }, config: config, agent: agent) }

      it "returns failure" do
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("seconds must be between 1 and 180")
      end
    end

    # ── Signal handling ─────────────────────────────────────────

    context "when cancel signal is received mid-sleep" do
      let(:executor) { described_class.new(input: { "seconds" => 10 }, config: config, agent: agent) }

      before do
        call_count = 0
        allow(SessionSignal).to receive(:check).with(session.id) do
          call_count += 1
          call_count >= 3 ? { type: "cancel" } : nil
        end
      end

      it "raises AgentInterrupted" do
        expect { executor.call }.to raise_error(AgentInterrupted)
      end

      it "does not sleep the full duration" do
        executor.call rescue AgentInterrupted
        expect(Kernel).to have_received(:sleep).at_most(3).times
      end
    end

    context "when redirect signal is received mid-sleep" do
      let(:executor) { described_class.new(input: { "seconds" => 10 }, config: config, agent: agent) }

      before do
        call_count = 0
        allow(SessionSignal).to receive(:check).with(session.id) do
          call_count += 1
          call_count >= 2 ? { type: "redirect", message: "do something else" } : nil
        end
      end

      it "raises AgentRedirected" do
        expect { executor.call }.to raise_error(AgentRedirected)
      end
    end

    # ── Without session ─────────────────────────────────────────

    context "without session" do
      let(:config) { {} }
      let(:executor) { described_class.new(input: { "seconds" => 2 }, config: config, agent: agent) }

      it "still sleeps successfully without broadcasting" do
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to eq("Waited 2 seconds")
        expect(ActionCable.server).not_to have_received(:broadcast)
      end

      it "does not check session signals" do
        executor.call

        expect(SessionSignal).not_to have_received(:check)
      end
    end
  end
end
