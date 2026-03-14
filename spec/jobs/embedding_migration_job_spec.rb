# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingMigrationJob, type: :job do
  let(:agent) { create(:agent) }
  let(:adapter) { instance_double(Embeddings::GeminiAdapter, capabilities: { modalities: [ :text, :image ] }) }
  let(:status) do
    EmbeddingMigrationStatus.create!(
      from_provider: "ollama", to_provider: "gemini", phase: "shadow", started_at: Time.current
    )
  end

  before do
    allow(Embeddings::Registry).to receive(:adapter_for).with("gemini").and_return(adapter)
  end

  it "re-embeds entries that lack shadow embeddings" do
    entry = MemoryEntry.create!(
      agent: agent,
      content: "test memory",
      memory_type: "semantic",
      embedding: Array.new(768) { 0.1 }
    )

    shadow_vector = Array.new(768) { 0.5 }
    allow(adapter).to receive(:embed_text).with("test memory").and_return(shadow_vector)

    described_class.perform_now(status.id)

    entry.reload
    expect(entry.shadow_embedding).to eq(shadow_vector)
  end

  it "skips entries that already have shadow embeddings" do
    existing_shadow = Array.new(768) { 0.3 }
    MemoryEntry.create!(
      agent: agent,
      content: "already done",
      memory_type: "semantic",
      embedding: Array.new(768) { 0.1 },
      shadow_embedding: existing_shadow
    )

    allow(adapter).to receive(:embed_text)
    described_class.perform_now(status.id)

    expect(adapter).not_to have_received(:embed_text)
  end

  it "does nothing if migration status is not active" do
    status.update!(phase: "complete")

    allow(adapter).to receive(:embed_text)
    described_class.perform_now(status.id)

    expect(adapter).not_to have_received(:embed_text)
  end

  it "handles embedding errors gracefully and continues" do
    MemoryEntry.create!(
      agent: agent,
      content: "will fail",
      memory_type: "semantic",
      embedding: Array.new(768) { 0.1 }
    )

    entry2 = MemoryEntry.create!(
      agent: agent,
      content: "will succeed",
      memory_type: "semantic",
      embedding: Array.new(768) { 0.1 }
    )

    shadow_vector = Array.new(768) { 0.5 }
    allow(adapter).to receive(:embed_text).with("will fail").and_raise(StandardError, "API error")
    allow(adapter).to receive(:embed_text).with("will succeed").and_return(shadow_vector)

    described_class.perform_now(status.id)

    entry2.reload
    expect(entry2.shadow_embedding).to eq(shadow_vector)
  end

  it "skips entries with blank content" do
    MemoryEntry.create!(
      agent: agent,
      content: "placeholder",
      memory_type: "semantic",
      embedding: Array.new(768) { 0.1 }
    )
    # Update content to empty after creation (bypasses presence validation)
    MemoryEntry.last.update_columns(content: "")

    allow(adapter).to receive(:embed_text)
    described_class.perform_now(status.id)

    expect(adapter).not_to have_received(:embed_text)
  end
end
