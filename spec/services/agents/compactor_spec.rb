# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Compactor do
  let(:agent) { build_stubbed(:agent) }
  subject(:compactor) { described_class.new(agent: agent, threshold: 50_000) }

  describe "#micro_compact!" do
    it "delegates to Agents::MicroCompact" do
      messages = [ { role: "user", content: "x" } ]
      expect(Agents::MicroCompact).to receive(:call).with(messages)
      compactor.micro_compact!(messages)
    end
  end

  describe "#auto_compact!" do
    it "delegates to Agents::AutoCompact with the agent" do
      messages = [ { role: "user", content: "x" } ]
      expect(Agents::AutoCompact).to receive(:call).with(messages, agent: agent)
      compactor.auto_compact!(messages)
    end
  end

  describe "#manual_compact!" do
    it "delegates to Agents::ManualCompact with the agent and focus" do
      messages = [ { role: "user", content: "x" } ]
      expect(Agents::ManualCompact).to receive(:call).with(messages, agent: agent, focus: "keep the migration plan")
      compactor.manual_compact!(messages, focus: "keep the migration plan")
    end
  end

  describe "#should_auto_compact?" do
    it "is false when estimated tokens stay under threshold" do
      expect(compactor.should_auto_compact?([ { role: "user", content: "hi" } ])).to be(false)
    end

    it "is true when estimated tokens exceed threshold" do
      tiny = described_class.new(agent: agent, threshold: 10)
      expect(tiny.should_auto_compact?([ { role: "user", content: "x" * 1000 } ])).to be(true)
    end
  end
end
