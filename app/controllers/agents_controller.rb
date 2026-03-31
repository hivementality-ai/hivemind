# frozen_string_literal: true

class AgentsController < ApplicationController
  before_action :set_agent, only: [ :show, :edit, :update, :destroy, :files, :upload_files, :delete_file, :create_directory, :download_file ]

  def index
    @agents = Agent.visible.includes(:team).order(:name)
  end

  def show
    @recent_sessions = @agent.sessions
                             .order(created_at: :desc)
                             .limit(10)

    @pending_approvals = ApprovalRequest.where(agent_id: @agent.id)
                                       .pending
                                       .not_expired
                                       .order(requested_at: :desc)

    @usage_today = @agent.usage_today
    @memories = MemoryEntry.where(agent: @agent).order(created_at: :desc).limit(20)
  end

  def new
    @agent = Agent.new
    @teams = Team.order(:name)
  end

  def create
    @agent = Agent.new(agent_params)
    assign_restricted_attrs(@agent)

    if @agent.save
      Plugins::Hooks.trigger("agent_created", agent: @agent)
      Agents::SyncSkillTools.call(agent: @agent)
      redirect_to @agent, notice: "Agent created successfully"
    else
      @teams = Team.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @teams = Team.order(:name)
  end

  def update
    old_skill_ids = @agent.skill_ids.dup
    @agent.assign_attributes(agent_params)
    assign_restricted_attrs(@agent)
    if @agent.save
      Agents::SyncSkillTools.call(agent: @agent, removed_skill_ids: old_skill_ids - @agent.skill_ids)
      redirect_to @agent, notice: "Agent updated successfully"
    else
      @teams = Team.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @agent.destroy
    redirect_to agents_url, notice: "Agent deleted successfully"
  rescue ActiveRecord::InvalidForeignKey => e
    Rails.logger.error("Failed to delete agent #{@agent.slug}: #{e.message}")
    redirect_to @agent, alert: "Unable to delete agent — it has associated records that could not be removed."
  end

  def files
    workspace = @agent.ensure_workspace!
    @current_path = params[:path].to_s
    dir = @current_path.present? ? resolve_agent_path(@current_path) : workspace

    unless dir
      redirect_to files_agent_path(@agent), alert: "Invalid path."
      return
    end

    entries = Dir.children(dir).sort.map do |name|
      full = File.join(dir, name)
      {
        name: name,
        directory: File.directory?(full),
        size: File.file?(full) ? File.size(full) : nil,
        modified: File.mtime(full)
      }
    end

    @directories = entries.select { |e| e[:directory] }
    @files = entries.reject { |e| e[:directory] }
    @breadcrumbs = build_breadcrumbs(@current_path)
  end

  def upload_files
    workspace = @agent.ensure_workspace!
    target_dir = params[:path].present? ? resolve_agent_path(params[:path]) : workspace

    unless target_dir
      redirect_to files_agent_path(@agent), alert: "Invalid path."
      return
    end

    saved = []
    Array(params[:files]).each do |upload|
      next unless upload.respond_to?(:original_filename)

      safe_name = upload.original_filename.gsub(/[^a-zA-Z0-9._-]/, "_")
      dest = File.join(target_dir, safe_name)

      if File.exist?(dest)
        ext = File.extname(safe_name)
        base = File.basename(safe_name, ext)
        safe_name = "#{base}_#{Time.current.strftime('%H%M%S')}#{ext}"
        dest = File.join(target_dir, safe_name)
      end

      File.binwrite(dest, upload.read)
      saved << safe_name
    end

    redirect_to files_agent_path(@agent, path: params[:path]), notice: "#{saved.size} file(s) uploaded."
  end

  def delete_file
    resolved = resolve_agent_path(params[:path])

    unless resolved
      redirect_to files_agent_path(@agent), alert: "Invalid file path."
      return
    end

    if File.file?(resolved)
      File.delete(resolved)
    elsif File.directory?(resolved) && Dir.empty?(resolved)
      Dir.rmdir(resolved)
    else
      redirect_to files_agent_path(@agent, path: params[:path]), alert: "Cannot delete non-empty directory."
      return
    end

    parent = File.dirname(params[:path].to_s)
    parent = nil if parent == "."
    redirect_to files_agent_path(@agent, path: parent), notice: "Deleted successfully."
  end

  def create_directory
    workspace = @agent.ensure_workspace!
    target_dir = params[:path].present? ? resolve_agent_path(params[:path]) : workspace

    unless target_dir
      redirect_to files_agent_path(@agent), alert: "Invalid path."
      return
    end

    name = params[:name].to_s.strip.gsub(/[^a-zA-Z0-9._-]/, "_")
    if name.blank?
      redirect_to files_agent_path(@agent, path: params[:path]), alert: "Invalid directory name."
      return
    end

    FileUtils.mkdir_p(File.join(target_dir, name))
    redirect_to files_agent_path(@agent, path: params[:path]), notice: "Directory '#{name}' created."
  end

  def download_file
    resolved = resolve_agent_path(params[:path])

    unless resolved && File.file?(resolved)
      redirect_to files_agent_path(@agent), alert: "File not found."
      return
    end

    send_file resolved, disposition: "attachment"
  end

  private

  def set_agent
    @agent = Agent.find_by_slug(params[:slug])
    render file: "public/404.html", status: :not_found unless @agent
  end

  def agent_params
    params.require(:agent).permit(
      :name, :team_id, :model_provider, :llm_model,
      :daily_budget_limit, :monthly_budget_limit, :workspace_path,
      :system_prompt, :custom_instructions, :enabled, :avatar,
      :thinking_enabled, :thinking_budget_tokens, :thinking_visibility,
      tool_ids: [],
      skill_ids: []
    )
  end

  MODEL_CONFIG_FIELDS = %w[context_window max_output_tokens temperature top_p top_k repeat_penalty].freeze

  def assign_restricted_attrs(agent)
    ap = params[:agent]
    return unless ap

    agent.role = ap[:role] if ap.key?(:role)
    agent.egress_policy_mode = ap[:egress_policy_mode] if ap.key?(:egress_policy_mode)
    agent.egress_policy_rules = ap[:egress_policy_rules] if ap.key?(:egress_policy_rules)
    agent.egress_policy_log_blocked = ap[:egress_policy_log_blocked] if ap.key?(:egress_policy_log_blocked)
    assign_model_config(agent)
  end

  def assign_model_config(agent)
    mc = agent.model_config || {}
    MODEL_CONFIG_FIELDS.each do |field|
      val = params[:agent][field]
      if val.present?
        mc[field] = val.to_f
        mc[field] = mc[field].to_i if %w[context_window max_output_tokens top_k].include?(field)
      else
        mc.delete(field)
      end
    end
    agent.model_config = mc
  end

  def resolve_agent_path(relative)
    relative = relative.to_s
    return nil if relative.blank? || relative.include?("..") || relative.start_with?("/")
    return nil if @agent.workspace_path.blank?

    workspace = File.realpath(@agent.workspace_path) rescue nil
    target = File.realpath(File.join(@agent.workspace_path, relative)) rescue nil

    return nil unless workspace && target && target.start_with?(workspace + "/")

    target
  end

  def build_breadcrumbs(path)
    return [] if path.blank?

    parts = path.split("/").reject(&:blank?)
    parts.each_with_index.map do |part, i|
      { name: part, path: parts[0..i].join("/") }
    end
  end
end
