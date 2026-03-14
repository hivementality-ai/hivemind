# frozen_string_literal: true

class EmbeddingMigrationsController < ApplicationController
  before_action :authenticate_user!

  def show
    @progress = Embeddings::Migration.progress
    @providers = Embeddings::Registry.available
    @current_provider = Embeddings::Registry.configured_provider
    @history = EmbeddingMigrationStatus.order(created_at: :desc).limit(10)
  end

  def start
    result = Embeddings::Migration.start_shadow_phase!(
      from_provider: params[:from_provider],
      to_provider: params[:to_provider]
    )

    redirect_to embedding_migration_path, notice: "Migration started from #{result.from_provider} to #{result.to_provider}"
  rescue Embeddings::Migration::Error => e
    redirect_to embedding_migration_path, alert: e.message
  end

  def validate
    Embeddings::Migration.validate!
    redirect_to embedding_migration_path, notice: "Validation complete — check results below"
  rescue Embeddings::Migration::Error => e
    redirect_to embedding_migration_path, alert: e.message
  end

  def cutover
    Embeddings::Migration.cutover!
    redirect_to embedding_migration_path, notice: "Cutover complete — embeddings swapped to new provider"
  rescue Embeddings::Migration::Error => e
    redirect_to embedding_migration_path, alert: e.message
  end

  def rollback
    Embeddings::Migration.rollback!
    redirect_to embedding_migration_path, notice: "Migration rolled back"
  rescue Embeddings::Migration::Error => e
    redirect_to embedding_migration_path, alert: e.message
  end

  def progress
    data = Embeddings::Migration.progress
    render json: data || { phase: "idle" }
  end
end
