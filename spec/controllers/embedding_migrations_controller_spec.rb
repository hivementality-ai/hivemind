# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingMigrationsController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
  end

  describe "GET #show" do
    it "renders the migration status page" do
      allow(Embeddings::Migration).to receive(:progress).and_return(nil)
      allow(Embeddings::Registry).to receive(:available).and_return([])
      allow(Embeddings::Registry).to receive(:configured_provider).and_return("ollama")

      get :show
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST #start" do
    it "starts a migration and redirects" do
      status = instance_double(EmbeddingMigrationStatus, from_provider: "ollama", to_provider: "gemini")
      allow(Embeddings::Migration).to receive(:start_shadow_phase!).and_return(status)

      post :start, params: { from_provider: "ollama", to_provider: "gemini" }

      expect(response).to redirect_to(embedding_migration_path)
      expect(flash[:notice]).to include("Migration started")
    end

    it "redirects with alert on error" do
      allow(Embeddings::Migration).to receive(:start_shadow_phase!)
        .and_raise(Embeddings::Migration::Error, "Migration already active")

      post :start, params: { from_provider: "ollama", to_provider: "gemini" }

      expect(response).to redirect_to(embedding_migration_path)
      expect(flash[:alert]).to eq("Migration already active")
    end
  end

  describe "POST #validate" do
    it "validates and redirects" do
      status = instance_double(EmbeddingMigrationStatus)
      allow(Embeddings::Migration).to receive(:validate!).and_return(status)

      post :validate
      expect(response).to redirect_to(embedding_migration_path)
      expect(flash[:notice]).to include("Validation complete")
    end

    it "redirects with alert on error" do
      allow(Embeddings::Migration).to receive(:validate!)
        .and_raise(Embeddings::Migration::Error, "No active migration found")

      post :validate
      expect(response).to redirect_to(embedding_migration_path)
      expect(flash[:alert]).to eq("No active migration found")
    end
  end

  describe "POST #cutover" do
    it "performs cutover and redirects" do
      status = instance_double(EmbeddingMigrationStatus)
      allow(Embeddings::Migration).to receive(:cutover!).and_return(status)

      post :cutover
      expect(response).to redirect_to(embedding_migration_path)
      expect(flash[:notice]).to include("Cutover complete")
    end
  end

  describe "POST #rollback" do
    it "rolls back and redirects" do
      status = instance_double(EmbeddingMigrationStatus)
      allow(Embeddings::Migration).to receive(:rollback!).and_return(status)

      post :rollback
      expect(response).to redirect_to(embedding_migration_path)
      expect(flash[:notice]).to include("rolled back")
    end
  end

  describe "GET #progress" do
    it "returns JSON progress data" do
      progress_data = { phase: "shadow", percent_complete: 45.0 }
      allow(Embeddings::Migration).to receive(:progress).and_return(progress_data)

      get :progress, format: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("phase" => "shadow")
    end

    it "returns idle when no migration active" do
      allow(Embeddings::Migration).to receive(:progress).and_return(nil)

      get :progress, format: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("phase" => "idle")
    end
  end
end
