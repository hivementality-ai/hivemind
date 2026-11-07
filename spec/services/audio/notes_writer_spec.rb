# frozen_string_literal: true

require "rails_helper"

RSpec.describe Audio::NotesWriter do
  let(:agent) { create(:agent) }
  let(:adapter) { instance_double(Providers::OpenaiAdapter) }

  before do
    allow(Providers::Resolver).to receive(:call).and_return(ServiceResponse.success(data: { adapter: adapter }))
  end

  it "asks the agent's model for the four sections and returns the reply" do
    sent = nil
    allow(adapter).to receive(:chat) do |messages:, options:|
      sent = { messages: messages, options: options }
      ServiceResponse.success(data: { content: "## Summary\nShort." })
    end

    notes = described_class.new(agent).call("Dana will send the quote.")

    expect(notes).to eq("## Summary\nShort.")
    expect(sent[:messages].first[:content]).to include("Summary", "Decisions", "Action items", "Open questions")
    expect(sent[:messages].last[:content]).to eq("Dana will send the quote.")
    expect(sent[:options][:model]).to eq(BackgroundModel.for(agent))
  end

  it "fails in plain words when no model is available" do
    allow(Providers::Resolver).to receive(:call).and_return(ServiceResponse.failure(error: "none"))

    expect { described_class.new(agent).call("hi") }.to raise_error(described_class::Failure, /No model is available/)
  end

  it "fails in plain words when the model errors or answers empty" do
    allow(adapter).to receive(:chat).and_return(ServiceResponse.failure(error: "rate limited"))
    expect { described_class.new(agent).call("hi") }.to raise_error(described_class::Failure, /rate limited/)

    allow(adapter).to receive(:chat).and_return(ServiceResponse.success(data: { content: " " }))
    expect { described_class.new(agent).call("hi") }.to raise_error(described_class::Failure, /empty notes/)
  end
end
