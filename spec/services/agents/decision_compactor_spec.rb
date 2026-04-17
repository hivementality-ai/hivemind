# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::DecisionCompactor do
  let(:context_manager) { instance_double(Agents::ContextManager) }
  let(:threshold) { 1000 }
  subject(:compactor) { described_class.new(context_manager: context_manager, threshold: threshold) }

  before do
    allow(Rails.logger).to receive(:info)
  end

  describe "milestone signals" do
    it "records specs_passed" do
      compactor.signal_specs_passed!
      expect(compactor.pending_trigger).to eq(:specs_passed)
    end

    it "records multi_file_edit_complete only when >1 file edited" do
      compactor.signal_file_edited!("a.rb")
      compactor.signal_edit_batch_complete!
      expect(compactor.pending_trigger).to be_nil

      compactor.signal_file_edited!("a.rb")
      compactor.signal_file_edited!("b.rb")
      compactor.signal_edit_batch_complete!
      expect(compactor.pending_trigger).to eq(:multi_file_edit_complete)
    end
  end

  describe "#detect_topic_switch" do
    it "fires on non-overlapping keywords" do
      compactor.detect_topic_switch("implement user authentication logic")
      compactor.detect_topic_switch("refactor payment processing pipeline")
      expect(compactor.pending_trigger).to eq(:topic_switch)
    end

    it "does not fire when keywords overlap" do
      compactor.detect_topic_switch("implement user authentication")
      compactor.detect_topic_switch("fix user authentication bug")
      expect(compactor.pending_trigger).to be_nil
    end
  end

  describe "#check!" do
    it "returns messages unchanged when no trigger is pending" do
      msgs = [ { role: "user", content: "hi" } ]
      expect(compactor.check!(msgs)).to eq(msgs)
    end

    it "returns messages unchanged when under the early-compact ratio" do
      allow(context_manager).to receive(:estimate_tokens_for).and_return(100)
      compactor.signal_specs_passed!

      msgs = [ { role: "user", content: "hi" } ]
      expect(compactor.check!(msgs)).to eq(msgs)
    end

    it "invokes prune_messages when trigger + estimate above ratio" do
      allow(context_manager).to receive(:estimate_tokens_for).and_return(800)
      allow(context_manager).to receive(:prune_messages).and_return([ :pruned ])
      compactor.signal_specs_passed!

      msgs = [ { role: "user", content: "hi" } ]
      result = compactor.check!(msgs)

      expect(context_manager).to have_received(:prune_messages).with(msgs)
      expect(result).to eq([ :pruned ])
      expect(compactor.pending_trigger).to be_nil
    end
  end
end
