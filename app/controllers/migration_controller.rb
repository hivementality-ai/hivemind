# frozen_string_literal: true

class MigrationController < ApplicationController
  before_action :authenticate_user!

  def upload; end

  def scan
    workspace_path = params[:workspace_path].to_s.strip
    agent_slug = params[:agent_slug].to_s.strip.presence

    unless workspace_path.present? && File.directory?(workspace_path)
      redirect_to migration_path, alert: "Invalid path: directory does not exist"
      return
    end

    result = OpenClaw::Migrator.call(workspace_path:, agent_slug:, dry_run: true)

    if result.success?
      report = result.data[:report]
      session[:pending_migration] = {
        workspace_path: workspace_path,
        agent_slug: agent_slug,
        report: report.to_h
      }
      redirect_to migration_results_path
    else
      redirect_to migration_path, alert: "Scan failed: #{result.error}"
    end
  end

  def results
    pending = session[:pending_migration]
    unless pending
      redirect_to migration_path, alert: "No scan results. Please start a new scan."
      return
    end

    @report = pending.deep_symbolize_keys[:report]
  end

  def review
    pending = session[:pending_migration]
    unless pending
      redirect_to migration_path, alert: "No pending migration. Please start a new scan."
      return
    end

    @report = pending.deep_symbolize_keys[:report]
  end

  def run_import
    pending = session[:pending_migration]
    unless pending
      redirect_to migration_path, alert: "No pending migration. Please start a new scan."
      return
    end

    pending = pending.deep_symbolize_keys
    workspace_path = pending[:workspace_path]
    agent_slug = pending[:agent_slug]

    result = OpenClaw::Migrator.call(workspace_path:, agent_slug:, dry_run: false)

    if result.success?
      session[:migration_result] = result.data[:report].to_h
      session.delete(:pending_migration)
      redirect_to migration_reconnect_path
    else
      redirect_to migration_review_path, alert: "Import failed: #{result.error}"
    end
  end

  def reconnect
    result = session[:migration_result]
    unless result
      redirect_to migration_path, alert: "No migration result found. Please start a new migration."
      return
    end

    @report = result.deep_symbolize_keys
    session.delete(:migration_result)
  end
end
