# frozen_string_literal: true

class SkillsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin_or_owner!, only: [ :proposals, :approve_proposal, :reject_proposal, :update_proposals, :approve_update_proposal, :reject_update_proposal, :history, :rollback ]
  before_action :set_skill, only: [ :show, :edit, :update, :destroy, :toggle, :approve_proposal, :reject_proposal, :history, :rollback ]
  before_action :set_update_proposal, only: [ :approve_update_proposal, :reject_update_proposal ]

  def index
    @skills = Skill.includes(:tools, :agents).order(:name)
    @categories = Skill.distinct.pluck(:category).compact.sort
    @pending_count = Skill.pending_proposals.count
    @pending_update_count = SkillUpdateProposal.pending.count

    respond_to do |format|
      format.html
      format.json { render json: skills_index_json(@skills) } # shareable discovery index
    end
  end

  # Download a portable bundle of skills (agentskills.io-compatible SKILL.md
  # each, wrapped in a JSON envelope) for sharing between Hivemind instances.
  def export_bundle
    skills = Skill.custom.order(:name)
    skills = skills.where(id: params[:ids]) if params[:ids].present?

    bundle = {
      format: "hivemind-skill-bundle",
      version: "1",
      exported_at: Time.current.iso8601,
      skills: skills.map { |s| { name: s.name, skill_md: s.to_skill_md } }
    }

    send_data JSON.pretty_generate(bundle),
              filename: "hivemind-skills-#{Date.current.iso8601}.json",
              type: "application/json"
  end

  # Ingest a bundle produced by #export_bundle. Every skill is security-scanned;
  # blocked ones are skipped.
  def import_bundle
    file = params[:file]
    unless file
      redirect_to skills_path, alert: "No bundle file selected"
      return
    end

    bundle = JSON.parse(file.read)
    entries = bundle["skills"] || []
    imported = []
    skipped = []

    entries.each do |entry|
      md = entry["skill_md"].presence || entry["content"].presence
      next if md.blank?

      skill = Skill.from_skill_md(md)
      next if skill.name.blank?

      skill.summary = skill.name if skill.summary.blank?
      scan = SkillSecurityScanner.call(content: skill.content, name: skill.name, source: "import")
      status = scan.success? ? scan.data[:status] : "error"

      if status == "blocked"
        skipped << "#{skill.name} (blocked)"
        next
      end

      attrs = {
        description: skill.description, summary: skill.summary, content: skill.content,
        category: skill.category, tags: skill.tags, source_url: skill.source_url,
        metadata: skill.metadata, source: "import",
        security_scan_result: scan.success? ? scan.data : {}
      }

      existing = Skill.find_by(name: skill.name)
      if existing
        existing.update(attrs)
        imported << skill.name
      else
        skill.assign_attributes(attrs)
        skill.save ? imported << skill.name : skipped << "#{skill.name} (invalid)"
      end
    end

    notice = "Imported #{imported.size} skill(s)."
    notice += " Skipped: #{skipped.join(', ')}." if skipped.any?
    redirect_to skills_path, notice: notice
  rescue JSON::ParserError
    redirect_to skills_path, alert: "Invalid bundle file (not valid JSON)"
  end

  def show; end

  def new
    @skill = Skill.new
  end

  def create
    @skill = Skill.new(skill_params)

    if @skill.save
      redirect_to skill_path(@skill), notice: "Skill created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @skill.update(skill_params)
      redirect_to skill_path(@skill), notice: "Skill updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @skill.name
    @skill.destroy
    redirect_to skills_path, notice: "#{name} deleted"
  end

  def toggle
    @skill.update(enabled: !@skill.enabled?)
    redirect_to skills_path, notice: "#{@skill.name} #{@skill.enabled? ? 'enabled' : 'disabled'}"
  end

  def import
    file = params[:file]
    unless file
      redirect_to skills_path, alert: "No file selected"
      return
    end

    content = file.read
    skill = Skill.from_skill_md(content)

    if skill.name.blank?
      skill.name = File.basename(file.original_filename, ".*").parameterize
    end

    scan_result = SkillSecurityScanner.call(content: skill.content, name: skill.name, source: "import")

    if scan_result.success? && scan_result.data[:status] == "clean"
      save_imported_skill(skill, scan_result.data)
    else
      # Store in cache instead of session to avoid CookieOverflow on large skills
      import_key = "skill_import_#{current_user.id}_#{SecureRandom.hex(8)}"
      Rails.cache.write(import_key, {
        name: skill.name,
        description: skill.description,
        summary: skill.summary,
        content: skill.content,
        category: skill.category,
        scan_result: scan_result.success? ? scan_result.data : { status: "error", error: scan_result.error }
      }, expires_in: 30.minutes)
      session[:pending_skill_import_key] = import_key
      redirect_to review_import_skills_path
    end
  end

  def review_import
    import_key = session[:pending_skill_import_key]
    @pending = import_key ? Rails.cache.read(import_key) : nil
    unless @pending
      redirect_to skills_path, alert: "No pending import to review"
      return
    end

    @scan_result = @pending["scan_result"] || @pending[:scan_result]
  end

  def confirm_import
    import_key = session[:pending_skill_import_key]
    pending = import_key ? Rails.cache.read(import_key) : nil
    unless pending
      redirect_to skills_path, alert: "No pending import to confirm"
      return
    end

    pending = pending.deep_symbolize_keys
    scan_result = pending[:scan_result]

    if scan_result[:status] == "blocked"
      redirect_to skills_path, alert: "Blocked skills cannot be imported"
      return
    end

    skill = Skill.from_skill_md("")
    skill.assign_attributes(
      name: pending[:name],
      description: pending[:description],
      summary: pending[:summary],
      content: pending[:content],
      category: pending[:category]
    )

    scan_result[:approved_by] = current_user.id
    scan_result[:approved_at] = Time.current.iso8601

    save_imported_skill(skill, scan_result, approved: true)
    Rails.cache.delete(import_key)
    session.delete(:pending_skill_import_key)
  end

  def export
    skill = Skill.find(params[:id])
    send_data skill.to_skill_md,
              filename: "#{skill.name}.SKILL.md",
              type: "text/markdown"
  end

  def proposals
    @pending_skills   = Skill.pending_proposals.includes(:proposing_agent).order(proposed_at: :desc)
    @approved_skills  = Skill.approved_proposals.includes(:proposing_agent).order(approved_at: :desc).limit(20)
    @rejected_skills  = Skill.rejected_proposals.includes(:proposing_agent).order(proposal_rejected_at: :desc).limit(20)
  end

  def approve_proposal
    result = Skills::ProposalApprover.call(
      skill: @skill,
      approved_by: current_user.id,
      notes: params[:notes]
    )

    if result.success?
      redirect_to proposals_skills_path, notice: "\"#{@skill.name}\" approved and activated."
    else
      redirect_to proposals_skills_path, alert: result.error
    end
  end

  def reject_proposal
    result = Skills::ProposalRejector.call(
      skill: @skill,
      rejected_by: current_user.id,
      notes: params[:notes]
    )

    if result.success?
      redirect_to proposals_skills_path, notice: "\"#{@skill.name}\" rejected."
    else
      redirect_to proposals_skills_path, alert: result.error
    end
  end


  # ── Skill Update Proposals (Phase 5) ──────────────────────────

  def update_proposals
    @pending_proposals  = SkillUpdateProposal.pending.includes(:skill, :proposed_by_agent).order(created_at: :desc)
    @approved_proposals = SkillUpdateProposal.approved.includes(:skill, :proposed_by_agent).order(reviewed_at: :desc).limit(20)
    @rejected_proposals = SkillUpdateProposal.rejected.includes(:skill, :proposed_by_agent).order(reviewed_at: :desc).limit(20)
  end

  def approve_update_proposal
    result = Skills::UpdateApprover.call(
      proposal: @update_proposal,
      approved_by: current_user.id,
      notes: params[:notes]
    )

    if result.success?
      redirect_to update_proposals_skills_path, notice: "Update to \"#{@update_proposal.skill.name}\" approved and applied."
    else
      redirect_to update_proposals_skills_path, alert: result.error
    end
  end

  def reject_update_proposal
    result = Skills::UpdateRejector.call(
      proposal: @update_proposal,
      rejected_by: current_user.id,
      notes: params[:notes]
    )

    if result.success?
      redirect_to update_proposals_skills_path, notice: "Update proposal for \"#{@update_proposal.skill.name}\" rejected."
    else
      redirect_to update_proposals_skills_path, alert: result.error
    end
  end

  # ── Skill Version History & Rollback (Phase 5) ────────────────

  def history
    @versions = @skill.skill_versions.reverse_chronological.includes(:proposing_agent)
  end

  def rollback
    version_number = params[:version_number].to_i
    result = Skills::Rollback.call(
      skill: @skill,
      version_number: version_number,
      rolled_back_by: current_user.id
    )

    if result.success?
      redirect_to history_skill_path(@skill), notice: "Rolled back \"#{@skill.name}\" to version #{version_number}."
    else
      redirect_to history_skill_path(@skill), alert: result.error
    end
  end

  private

  def set_skill
    @skill = Skill.find(params[:id])
  end

  def skill_params
    params.require(:skill).permit(:name, :description, :summary, :content, :category, :enabled, tool_ids: [])
  end

  def set_update_proposal
    @update_proposal = SkillUpdateProposal.find(params[:id])
  end

  def skills_index_json(skills)
    {
      format: "hivemind-skill-index",
      version: "1",
      skills: skills.map do |s|
        {
          name: s.name, description: s.description, category: s.category,
          tier: s.tier, tags: s.tags, source: s.source,
          security_status: s.security_status, agents_count: s.agents.size,
          checksum: s.checksum
        }
      end
    }
  end

  def save_imported_skill(skill, scan_data, approved: false)
    existing = Skill.find_by(name: skill.name)

    attrs = {
      description: skill.description,
      summary: skill.summary,
      content: skill.content,
      category: skill.category,
      source: "import",
      security_scan_result: scan_data
    }

    if approved
      attrs[:approved_by] = current_user.id
      attrs[:approved_at] = Time.current
    end

    if existing
      existing.update(attrs)
      redirect_to skill_path(existing), notice: "#{existing.name} updated from import"
    else
      skill.assign_attributes(attrs)
      if skill.save
        redirect_to skill_path(skill), notice: "#{skill.name} imported"
      else
        redirect_to skills_path, alert: "Import failed: #{skill.errors.full_messages.join(', ')}"
      end
    end
  end
end
