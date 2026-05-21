# frozen_string_literal: true

class SkillsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_skill, only: [ :show, :edit, :update, :destroy, :toggle, :approve_proposal, :reject_proposal ]

  def index
    @skills = Skill.includes(:tools, :agents).order(:name)
    @categories = Skill.distinct.pluck(:category).compact.sort
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

  private

  def set_skill
    @skill = Skill.find(params[:id])
  end

  def skill_params
    params.require(:skill).permit(:name, :description, :summary, :content, :category, :enabled, tool_ids: [])
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
