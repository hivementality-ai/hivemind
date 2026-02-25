# frozen_string_literal: true

class SkillsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_skill, only: [ :show, :edit, :update, :destroy, :toggle ]

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

    existing = Skill.find_by(name: skill.name)
    if existing
      existing.update(description: skill.description, summary: skill.summary, content: skill.content, category: skill.category)
      redirect_to skill_path(existing), notice: "#{existing.name} updated from import"
    else
      if skill.save
        redirect_to skill_path(skill), notice: "#{skill.name} imported"
      else
        redirect_to skills_path, alert: "Import failed: #{skill.errors.full_messages.join(', ')}"
      end
    end
  end

  def export
    skill = Skill.find(params[:id])
    send_data skill.to_skill_md,
              filename: "#{skill.name}.SKILL.md",
              type: "text/markdown"
  end

  private

  def set_skill
    @skill = Skill.find(params[:id])
  end

  def skill_params
    params.require(:skill).permit(:name, :description, :summary, :content, :category, :enabled, tool_ids: [])
  end
end
