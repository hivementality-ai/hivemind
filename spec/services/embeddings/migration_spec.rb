# frozen_string_literal: true

require "rails_helper"

RSpec.describe Embeddings::Migration, type: :service do
  let(:ollama_adapter) { instance_double(Embeddings::OllamaAdapter, healthy?: true, capabilities: { modalities: [ :text ] }) }
  let(:gemini_adapter) { instance_double(Embeddings::GeminiAdapter, healthy?: true, capabilities: { modalities: [ :text, :image ] }) }

  before do
    allow(Embeddings::Registry).to receive(:adapter_for).with("ollama").and_return(ollama_adapter)
    allow(Embeddings::Registry).to receive(:adapter_for).with("gemini").and_return(gemini_adapter)
  end

  describe ".start_shadow_phase!" do
    it "creates a migration status and enables dual-write" do
      allow(EmbeddingMigrationJob).to receive(:perform_later)

      status = described_class.start_shadow_phase!(from_provider: "ollama", to_provider: "gemini")

      expect(status).to be_persisted
      expect(status.phase).to eq("shadow")
      expect(status.from_provider).to eq("ollama")
      expect(status.to_provider).to eq("gemini")
      expect(status.started_at).to be_present
      expect(Setting.get("embedding_migration_active")).to eq("true")
      expect(Setting.get("embedding_migration_target")).to eq("gemini")
    end

    it "enqueues the batch re-embedding job" do
      allow(EmbeddingMigrationJob).to receive(:perform_later)

      status = described_class.start_shadow_phase!(from_provider: "ollama", to_provider: "gemini")

      expect(EmbeddingMigrationJob).to have_received(:perform_later).with(status.id)
    end

    it "raises if a migration is already active" do
      EmbeddingMigrationStatus.create!(from_provider: "ollama", to_provider: "gemini", phase: "shadow")

      expect {
        described_class.start_shadow_phase!(from_provider: "ollama", to_provider: "gemini")
      }.to raise_error(Embeddings::Migration::Error, /already active/)
    end

    it "raises for unknown target provider" do
      expect {
        described_class.start_shadow_phase!(from_provider: "ollama", to_provider: "unknown")
      }.to raise_error(Embeddings::Migration::Error, /Unknown target provider/)
    end

    it "raises if target provider is not healthy" do
      allow(gemini_adapter).to receive(:healthy?).and_return(false)

      expect {
        described_class.start_shadow_phase!(from_provider: "ollama", to_provider: "gemini")
      }.to raise_error(Embeddings::Migration::Error, /not healthy/)
    end
  end

  describe ".validate!" do
    it "runs validation and updates status" do
      status = EmbeddingMigrationStatus.create!(
        from_provider: "ollama", to_provider: "gemini", phase: "shadow", started_at: Time.current
      )

      fake_results = { coverage_percent: 100, avg_result_overlap: 0.8, pass: true }
      validation_service = instance_double(Embeddings::ValidationService, validate: fake_results)
      allow(Embeddings::ValidationService).to receive(:new).with(status).and_return(validation_service)

      result = described_class.validate!(status.id)

      expect(result.phase).to eq("validated")
      expect(result.validated_at).to be_present
      expect(result.validation_results).to include("pass" => true)
    end

    it "raises if no active migration" do
      expect {
        described_class.validate!
      }.to raise_error(Embeddings::Migration::Error, /No active migration/)
    end

    it "raises if migration is not in shadow phase" do
      status = EmbeddingMigrationStatus.create!(
        from_provider: "ollama", to_provider: "gemini", phase: "validated"
      )

      expect {
        described_class.validate!(status.id)
      }.to raise_error(Embeddings::Migration::Error, /not in shadow phase/)
    end
  end

  describe ".cutover!" do
    it "swaps columns and completes migration" do
      status = EmbeddingMigrationStatus.create!(
        from_provider: "ollama", to_provider: "gemini", phase: "validated", started_at: Time.current
      )

      conn = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
      allow(ActiveRecord::Base).to receive(:connection).and_return(conn)
      allow(conn).to receive(:execute)

      result = described_class.cutover!(status.id)

      expect(result.phase).to eq("complete")
      expect(result.completed_at).to be_present
      expect(Setting.get("embedding_migration_active")).to eq("false")
      expect(conn).to have_received(:execute).with("ALTER TABLE memory_entries RENAME COLUMN embedding TO old_embedding")
      expect(conn).to have_received(:execute).with("ALTER TABLE memory_entries RENAME COLUMN shadow_embedding TO embedding")
      expect(conn).to have_received(:execute).with("ALTER TABLE memory_entries RENAME COLUMN old_embedding TO shadow_embedding")
    end

    it "raises if migration not validated" do
      status = EmbeddingMigrationStatus.create!(
        from_provider: "ollama", to_provider: "gemini", phase: "shadow"
      )

      expect {
        described_class.cutover!(status.id)
      }.to raise_error(Embeddings::Migration::Error, /must be validated/)
    end
  end

  describe ".rollback!" do
    it "clears shadow embeddings and marks rolled back" do
      status = EmbeddingMigrationStatus.create!(
        from_provider: "ollama", to_provider: "gemini", phase: "shadow", started_at: Time.current
      )

      result = described_class.rollback!(status.id)

      expect(result.phase).to eq("rolled_back")
      expect(result.rolled_back_at).to be_present
      expect(Setting.get("embedding_migration_active")).to eq("false")
    end

    it "raises if migration is already complete" do
      status = EmbeddingMigrationStatus.create!(
        from_provider: "ollama", to_provider: "gemini", phase: "complete"
      )

      expect {
        described_class.rollback!(status.id)
      }.to raise_error(Embeddings::Migration::Error, /Cannot rollback a completed/)
    end
  end

  describe ".progress" do
    it "returns nil when no active migration" do
      expect(described_class.progress).to be_nil
    end

    it "returns progress data for active migration" do
      status = EmbeddingMigrationStatus.create!(
        from_provider: "ollama", to_provider: "gemini", phase: "shadow", started_at: Time.current
      )

      progress = described_class.progress

      expect(progress[:id]).to eq(status.id)
      expect(progress[:phase]).to eq("shadow")
      expect(progress[:from_provider]).to eq("ollama")
      expect(progress[:to_provider]).to eq("gemini")
      expect(progress).to have_key(:percent_complete)
    end
  end
end
