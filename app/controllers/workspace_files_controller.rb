# frozen_string_literal: true

class WorkspaceFilesController < ApplicationController
  ROOTS = {
    "workspace" => { path: "/workspace", label: "Workspace", icon: "folder" },
    "shared" => { path: Rails.root.join("agents-shared").to_s, label: "Shared Space", icon: "share" }
  }.freeze

  before_action :set_root

  def index
    dir = @current_path.present? ? resolve_path(@current_path) : @root_config[:path]

    unless dir && File.directory?(dir)
      redirect_to workspace_files_path(root: @root), alert: "Invalid path."
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

  def upload
    target_dir = @current_path.present? ? resolve_path(@current_path) : @root_config[:path]

    unless target_dir && File.directory?(target_dir)
      redirect_to workspace_files_path(root: @root), alert: "Invalid path."
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

    redirect_to workspace_files_path(root: @root, path: @current_path), notice: "#{saved.size} file(s) uploaded."
  end

  def delete
    resolved = resolve_path(params[:path])

    unless resolved
      redirect_to workspace_files_path(root: @root), alert: "Invalid file path."
      return
    end

    if File.file?(resolved)
      File.delete(resolved)
    elsif File.directory?(resolved) && Dir.empty?(resolved)
      Dir.rmdir(resolved)
    else
      redirect_to workspace_files_path(root: @root, path: params[:path]), alert: "Cannot delete non-empty directory."
      return
    end

    parent = File.dirname(params[:path].to_s)
    parent = nil if parent == "."
    redirect_to workspace_files_path(root: @root, path: parent), notice: "Deleted successfully."
  end

  def create_directory
    target_dir = @current_path.present? ? resolve_path(@current_path) : @root_config[:path]

    unless target_dir && File.directory?(target_dir)
      redirect_to workspace_files_path(root: @root), alert: "Invalid path."
      return
    end

    name = params[:name].to_s.strip.gsub(/[^a-zA-Z0-9._-]/, "_")
    if name.blank?
      redirect_to workspace_files_path(root: @root, path: @current_path), alert: "Invalid directory name."
      return
    end

    FileUtils.mkdir_p(File.join(target_dir, name))
    redirect_to workspace_files_path(root: @root, path: @current_path), notice: "Directory '#{name}' created."
  end

  def download
    resolved = resolve_path(params[:path])

    unless resolved && File.file?(resolved)
      redirect_to workspace_files_path(root: @root), alert: "File not found."
      return
    end

    send_file resolved, disposition: "attachment"
  end

  private

  def set_root
    @root = ROOTS.key?(params[:root]) ? params[:root] : "workspace"
    @root_config = ROOTS[@root]
    @current_path = params[:path].to_s.presence
    FileUtils.mkdir_p(@root_config[:path]) unless File.directory?(@root_config[:path])
  end

  def resolve_path(relative)
    relative = relative.to_s
    return nil if relative.blank? || relative.include?("..") || relative.start_with?("/")

    root_real = File.realpath(@root_config[:path]) rescue nil
    target = File.realpath(File.join(@root_config[:path], relative)) rescue nil

    return nil unless root_real && target && target.start_with?(root_real + "/")

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
