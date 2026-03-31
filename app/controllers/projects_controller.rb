# frozen_string_literal: true

class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :edit, :update, :pause, :resume, :cancel, :archive, :destroy, :upload_files, :delete_file ]

  def index
    @projects = Project.visible.includes(:team, :milestones).order(updated_at: :desc)
    @pending_approvals = ProjectMilestone.awaiting_review.count
  end

  def show
    @milestones = @project.milestones.includes(:agent, :session).ordered
    @events = @project.events.includes(:agent, :user, :project_milestone).recent.limit(50)
    @pending_milestones = @milestones.select { |m| m.status == "needs_review" }
    @project_files = @project.project_files
  end

  def new
    @project = Project.new
    @teams = Team.includes(:agents).order(:name)
  end

  def create
    @project = Project.new(project_params)
    @project.user = current_user

    if @project.save
      @project.ensure_workspace!

      # Save uploaded files during creation
      if params[:files].present?
        save_uploaded_files(params[:files])
      end

      if params[:ai_assisted] == "1" && @project.description.present?
        Projects::MilestonePlanner.call(project: @project)
      end

      if params[:milestones].present?
        create_manual_milestones
      end

      Projects::EventLogger.call(
        project: @project,
        user: current_user,
        event_type: "project_created",
        summary: "Project created: #{@project.title}"
      )

      redirect_to project_path(@project), notice: "Project created successfully."
    else
      @teams = Team.includes(:agents).order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @project.update(project_params)
      redirect_to project_path(@project), notice: "Project updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def pause
    @project.update!(status: "paused")
    Projects::EventLogger.call(project: @project, user: current_user,
      event_type: "status_change", summary: "Project paused by #{current_user.email}")
    redirect_to project_path(@project), notice: "Project paused."
  end

  def resume
    @project.update!(status: "active", started_at: @project.started_at || Time.current)
    Projects::EventLogger.call(project: @project, user: current_user,
      event_type: "status_change", summary: "Project resumed by #{current_user.email}")
    redirect_to project_path(@project), notice: "Project resumed."
  end

  def cancel
    @project.update!(status: "cancelled")
    Projects::EventLogger.call(project: @project, user: current_user,
      event_type: "status_change", summary: "Project cancelled by #{current_user.email}")
    redirect_to projects_path, notice: "Project cancelled."
  end

  def archive
    @project.update!(status: "archived")
    Projects::EventLogger.call(project: @project, user: current_user,
      event_type: "status_change", summary: "Project archived by #{current_user.email}")
    redirect_to projects_path, notice: "Project archived."
  end

  def destroy
    @project.destroy!
    redirect_to projects_path, notice: "Project deleted."
  rescue ActiveRecord::InvalidForeignKey
    redirect_to project_path(@project), alert: "Unable to delete — archive it instead."
  end

  def upload_files
    files = params[:files]
    if files.blank?
      redirect_to project_path(@project), alert: "No files selected."
      return
    end

    @project.ensure_workspace!
    saved = []

    Array(files).each do |upload|
      next unless upload.respond_to?(:original_filename)

      safe_name = upload.original_filename.gsub(/[^a-zA-Z0-9._-]/, "_")
      dest = File.join(@project.workspace_path, safe_name)

      # Don't overwrite — append timestamp if file exists
      if File.exist?(dest)
        ext = File.extname(safe_name)
        base = File.basename(safe_name, ext)
        safe_name = "#{base}_#{Time.current.strftime('%H%M%S')}#{ext}"
        dest = File.join(@project.workspace_path, safe_name)
      end

      File.binwrite(dest, upload.read)
      saved << safe_name
    end

    Projects::EventLogger.call(
      project: @project,
      user: current_user,
      event_type: "files_uploaded",
      summary: "#{saved.size} file(s) uploaded: #{saved.join(', ')}"
    )

    redirect_to project_path(@project), notice: "#{saved.size} file(s) uploaded."
  end

  def delete_file
    relative_path = params[:path].to_s
    if relative_path.blank? || relative_path.include?("..") || relative_path.start_with?("/")
      redirect_to project_path(@project), alert: "Invalid file path."
      return
    end

    # Resolve to real path to prevent symlink traversal
    workspace = File.realpath(@project.workspace_path) rescue nil
    full_path = File.realpath(File.join(@project.workspace_path, relative_path)) rescue nil

    unless workspace && full_path && full_path.start_with?(workspace) && File.file?(full_path)
      redirect_to project_path(@project), alert: "File not found."
      return
    end

    File.delete(full_path)

    Projects::EventLogger.call(
      project: @project,
      user: current_user,
      event_type: "file_deleted",
      summary: "File deleted: #{relative_path}"
    )

    redirect_to project_path(@project), notice: "File deleted."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:title, :description, :team_id, :lead_agent_id, :priority, :deadline,
      notification_prefs: {})
  end

  def save_uploaded_files(files)
    Array(files).each do |upload|
      next unless upload.respond_to?(:original_filename)

      safe_name = upload.original_filename.gsub(/[^a-zA-Z0-9._-]/, "_")
      File.binwrite(File.join(@project.workspace_path, safe_name), upload.read)
    end
  end

  def create_manual_milestones
    params[:milestones].each_with_index do |m, idx|
      next if m[:title].blank?
      @project.milestones.create!(
        title: m[:title],
        description: m[:description],
        acceptance_criteria: m[:acceptance_criteria],
        position: idx,
        requires_approval: m[:requires_approval] != "0",
        agent_id: m[:agent_id].presence
      )
    end
  end
end
