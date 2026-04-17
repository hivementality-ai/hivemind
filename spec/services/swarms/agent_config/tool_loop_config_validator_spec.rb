# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::ToolLoopConfigValidator do
  def call(config)
    described_class.call(config: config)
  end

  describe "nil / blank input" do
    it "succeeds on nil" do
      expect(call(nil)).to be_success
    end

    it "succeeds on empty hash" do
      expect(call({})).to be_success
    end
  end

  describe "type check" do
    it "fails when config is not a hash" do
      result = call("30")
      expect(result).to be_error
      expect(result.payload[:errors]).to include("tool_loop_config must be an object")
    end
  end

  describe "positive integer fields" do
    %w[history_size warning_threshold critical_threshold circuit_breaker_threshold].each do |key|
      it "succeeds when #{key} is a positive integer" do
        expect(call({ key => 5 })).to be_success
      end

      it "fails when #{key} is zero" do
        result = call({ key => 0 })
        expect(result).to be_error
        expect(result.payload[:errors].first).to match(/#{key}.*positive integer/)
      end

      it "fails when #{key} is negative" do
        result = call({ key => -1 })
        expect(result).to be_error
      end

      it "fails when #{key} is a string" do
        result = call({ key => "five" })
        expect(result).to be_error
      end
    end
  end

  describe "threshold ordering" do
    it "succeeds when warning < critical < circuit_breaker" do
      result = call({
        "warning_threshold"           => 5,
        "critical_threshold"          => 10,
        "circuit_breaker_threshold"   => 50
      })
      expect(result).to be_success
    end

    it "fails when warning >= critical" do
      result = call({
        "warning_threshold"         => 10,
        "critical_threshold"        => 10,
        "circuit_breaker_threshold" => 50
      })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/warning_threshold.*less than critical_threshold/)
    end

    it "fails when critical >= circuit_breaker" do
      result = call({
        "warning_threshold"         => 5,
        "critical_threshold"        => 50,
        "circuit_breaker_threshold" => 50
      })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/critical_threshold.*less than circuit_breaker_threshold/)
    end

    it "skips ordering check when only one threshold is present" do
      expect(call({ "warning_threshold" => 10 })).to be_success
    end
  end

  describe "detectors validation" do
    it "succeeds when detectors are valid booleans" do
      result = call({
        "detectors" => {
          "generic_repeat" => true,
          "ping_pong"      => false,
          "no_progress"    => true
        }
      })
      expect(result).to be_success
    end

    it "fails when detectors is not a hash" do
      result = call({ "detectors" => ["generic_repeat"] })
      expect(result).to be_error
      expect(result.payload[:errors]).to include("tool_loop_config.detectors must be an object")
    end

    it "fails when a detector value is not a boolean" do
      result = call({ "detectors" => { "generic_repeat" => "yes" } })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/detectors\.generic_repeat.*boolean/)
    end
  end
end
