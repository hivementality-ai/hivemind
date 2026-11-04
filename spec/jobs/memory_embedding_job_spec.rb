# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryEmbeddingJob, type: :job do
  include ActiveJob::TestHelper

  let(:entry) { create(:memory_entry) }

  before do
    allow(Embeddings::Registry).to receive(:current)
      .and_return(instance_double(Embeddings::OllamaAdapter, embed_text: nil).tap do |a|
        allow(a).to receive(:embed_text).and_raise(Faraday::ConnectionFailed, "refused")
      end)
  end

  it "retries with backoff instead of returning silently when the provider is unreachable" do
    expect { described_class.perform_now(entry.id) }
      .to have_enqueued_job(described_class).with(entry.id)
  end

  it "gives up with a single warning after the attempts are exhausted" do
    allow(Rails.logger).to receive(:warn)
    perform_enqueued_jobs(only: described_class) do
      described_class.perform_later(entry.id)
    end
    expect(Rails.logger).to have_received(:warn).with(/giving up on entry #{entry.id}/).once
  end
end
