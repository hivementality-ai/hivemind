# frozen_string_literal: true

# Handles the multi-step swarm import UI flow.
#
# Swarm imports are not tied to an existing team — the .swarm.json defines the
# team to create (or update). The controller lives under the /teams collection
# so it is logically grouped with team management.
#
#   Step 1 — import_swarm (GET)
#     Render the file-upload form.
#
#   Step 2 — upload_swarm (POST)
#     Accept the .swarm.json upload, parse it with SwarmParser, run
#     SwarmConflictDetector, then cache the parse result and redirect to preview.
#     Parse errors are rendered inline on the upload form.
#
#   Step 3 — preview_swarm (GET)
#     Render the preview form: variable inputs (pre-filled from document defaults),
#     vault secret status indicators, and per-entity conflict resolution selectors.
#
#   Step 4 — confirm_swarm (POST)
#     Load cached parse state, apply user-supplied variable overrides and
#     conflict resolutions, and run SwarmImporter end-to-end. On success render
#     the post-deploy report. On failure re-render preview with the error.
#
# Cache key: "swarm_import_#{current_user.id}_#{hex_token}" — TTL 30 minutes.
# The key is kept in the session under :swarm_import_key.
class SwarmImportsController < ApplicationController
  before_action :authenticate_user!

  # GET /teams/import_swarm
  def import_swarm
    # Nothing to load — just render the upload form.
  end

  # POST /teams/upload_swarm
  def upload_swarm
    file = params[:swarm_file]

    unless file
      flash.now[:alert] = "No file selected. Please choose a .swarm.json file."
      render :import_swarm, status: :unprocessable_entity
      return
    end

    unless file.original_filename.end_with?(".swarm.json", ".json")
      flash.now[:alert] = "Invalid file type. Please upload a .swarm.json file."
      render :import_swarm, status: :unprocessable_entity
      return
    end

    raw_json = file.read.force_encoding("UTF-8")

    parse_result = Swarms::SwarmParser.call(json: raw_json)

    unless parse_result.success?
      @parse_errors = parse_result.payload&.dig(:errors) || [parse_result.message]
      render :import_swarm, status: :unprocessable_entity
      return
    end

    document = parse_result.payload

    conflict_result = Swarms::SwarmConflictDetector.call(document: document)
    conflict_report = conflict_result.payload

    import_key = "swarm_import_#{current_user.id}_#{SecureRandom.hex(8)}"
    Rails.cache.write(import_key, {
      raw_json:      raw_json,
      filename:      file.original_filename,
      swarm_name:    document.name,
      swarm_version: document.swarm_version,
      description:   document.description,
      variables:     serialize_variables(document.variables),
      conflicts:     serialize_conflicts(conflict_report.conflicts)
    }, expires_in: 30.minutes)

    session[:swarm_import_key] = import_key

    redirect_to preview_swarm_teams_path
  end

  # GET /teams/preview_swarm
  def preview_swarm
    @pending = load_pending_import
    unless @pending
      redirect_to import_swarm_teams_path,
                  alert: "Import session expired. Please upload the file again."
      return
    end

    @swarm_name  = @pending[:swarm_name]
    @description = @pending[:description]
    @variables   = @pending[:variables]
    @conflicts   = @pending[:conflicts]
  end

  # POST /teams/confirm_swarm
  def confirm_swarm
    pending = load_pending_import
    unless pending
      redirect_to import_swarm_teams_path,
                  alert: "Import session expired. Please upload the file again."
      return
    end

    variable_overrides = build_variable_overrides
    resolutions        = build_resolutions

    result = Swarms::SwarmImporter.call(
      json:               pending[:raw_json],
      variable_overrides: variable_overrides,
      resolutions:        resolutions
    )

    if result.success?
      report = result.payload[:report]
      clear_pending_import
      render :report, locals: { report: report }, status: :ok
    else
      @pending      = pending
      @swarm_name   = pending[:swarm_name]
      @description  = pending[:description]
      @variables    = pending[:variables]
      @conflicts    = pending[:conflicts]
      @import_error = result.message
      @import_stage = result.payload&.dig(:stage)
      render :preview_swarm, status: :unprocessable_entity
    end
  end

  private

  # -------------------------------------------------------------------------
  # Cache helpers
  # -------------------------------------------------------------------------

  def load_pending_import
    key = session[:swarm_import_key]
    return nil if key.blank?

    raw = Rails.cache.read(key)
    raw&.deep_symbolize_keys
  end

  def clear_pending_import
    key = session.delete(:swarm_import_key)
    Rails.cache.delete(key) if key.present?
  end

  # -------------------------------------------------------------------------
  # Param builders
  # -------------------------------------------------------------------------

  def build_variable_overrides
    raw = params[:variables]
    return {} unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

    raw.to_unsafe_h.transform_keys(&:to_s).transform_values { |v| v.to_s.strip }
  end

  def build_resolutions
    raw = params[:resolutions]
    return {} unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

    raw.to_unsafe_h.transform_keys(&:to_s).transform_values { |v| v.to_sym }
  end

  # -------------------------------------------------------------------------
  # Serializers for cache storage
  # -------------------------------------------------------------------------

  # Converts document.variables Hash<String, SwarmVariable> to an Array of plain
  # hashes safe for cache storage and template rendering.
  def serialize_variables(variables)
    return [] if variables.blank?

    variables.map do |name, var|
      {
        name:        name,
        description: var.description,
        required:    var.required,
        type:        var.type,
        default:     var.default
      }
    end
  end

  # Converts an Array<SwarmConflictDetector::Conflict> to plain hashes for cache storage.
  def serialize_conflicts(conflicts)
    return [] if conflicts.blank?

    conflicts.map do |conflict|
      {
        entity_type: conflict.entity_type.to_s,
        name:        conflict.name
      }
    end
  end
end
