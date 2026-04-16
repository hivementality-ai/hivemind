# frozen_string_literal: true

class TaskTemplatesController < ApplicationController
  before_action :set_template, only: [ :show, :edit, :update, :destroy ]

  def index
    @templates = TaskTemplate.includes(:task_hooks).order(:name)
  end

  def show
    @hooks = @template.task_hooks.includes(:skill).ordered
    @skills = Skill.enabled.order(:name)
  end

  def new
    @template = TaskTemplate.new(default_priority: "medium")
    @skills = Skill.enabled.order(:name)
  end

  def create
    @template = TaskTemplate.new(template_params)

    if @template.save
      redirect_to task_template_path(@template), notice: "Template created."
    else
      @skills = Skill.enabled.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @skills = Skill.enabled.order(:name)
  end

  def update
    if @template.update(template_params)
      redirect_to task_template_path(@template), notice: "Template updated."
    else
      @skills = Skill.enabled.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    redirect_to task_templates_path, notice: "Template deleted."
  end

  private

  def set_template
    @template = TaskTemplate.find(params[:id])
  end

  def template_params
    params.require(:task_template).permit(:name, :description, :default_priority)
  end
end
