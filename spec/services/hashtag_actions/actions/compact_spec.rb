# frozen_string_literal: true

require "rails_helper"

RSpec.describe HashtagActions::Actions::Compact do
  let(:agent) { create(:agent) }
  let(:session) do
    create(:session,
      agent: agent,
      transcript: [
        { "role" => "user", "content" => "what's the plan", "timestamp" => "t1" },
        { "role" => "assistant", "content" => "three steps...", "timestamp" => "t2" }
      ]
    )
  end

  context "when the session is empty" do
    before { session.update!(transcript: []) }

    it "returns a friendly response without calling the LLM" do
      result = described_class.call(agent: agent, session: session)
      expect(result[:status]).to eq("empty")
      expect(result[:response]).to include("Nothing to compact")
    end
  end

  context "when ManualCompact succeeds" do
    before do
      allow(Agents::ManualCompact).to receive(:call).and_return(
        [ { "role" => "user", "content" => "[Context compacted — manual]\n\n- did X\n- currently Y" } ]
      )
    end

    it "replaces the session transcript with the summary and bypasses the LLM" do
      result = described_class.call(agent: agent, session: session, payload: "keep migration plan")

      expect(result[:status]).to eq("compacted")
      expect(result[:bypass]).to be(true)
      expect(result[:response]).to include("Session compacted (2 → 1")

      session.reload
      expect(session.transcript.size).to eq(1)
      expect(session.transcript.first["content"]).to start_with("[Context compacted — manual]")
      expect(session.metadata["pre_compact_transcripts"]).to be_present
    end

    it "forwards the focus payload to ManualCompact" do
      described_class.call(agent: agent, session: session, payload: "keep migration plan")
      expect(Agents::ManualCompact).to have_received(:call).with(
        anything,
        agent: agent,
        focus: "keep migration plan"
      )
    end
  end

  context "when ManualCompact returns nil (no Anthropic configured)" do
    before { allow(Agents::ManualCompact).to receive(:call).and_return(nil) }

    it "returns a failure response and leaves the transcript untouched" do
      result = described_class.call(agent: agent, session: session)
      expect(result[:status]).to eq("failed")
      expect(session.reload.transcript.size).to eq(2)
    end
  end
end
