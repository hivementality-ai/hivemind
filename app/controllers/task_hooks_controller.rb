# frozen_string_literal: true

class TaskHooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, except: :overview
  before_action :set_hook, only: %i[edit update destroy toggle]

  def overview
    @teams = Team.includes(:agents, task_hooks: [:skill, :agent]).order(:name)
  end

  def index
    @hooks = @team.task_hooks.includes(:skill, :agent).ordered
    @skills = Skill.enabled.order(:name)
    @agents = @team.agents.enabled.order(:name)
  end

  def create
    @hook = @team.task_hooks.build(hook_params)
    @hook.position = @team.task_hooks.count

    if @hook.save
      redirect_to team_task_hooks_path(@team), notice: "Hook added."
    else
      @hooks = @team.task_hooks.includes(:skill, :agent).ordered
      @skills = Skill.enabled.order(:name)
      @agents = @team.agents.enabled.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @skills = Skill.enabled.order(:name)
    @agents = @team.agents.enabled.order(:name)
  end

  def update
    if @hook.update(hook_params)
      redirect_to team_task_hooks_path(@team), notice: "Hook updated."
    else
      @skills = Skill.enabled.order(:name)
      @agents = @team.agents.enabled.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @hook.destroy
    redirect_to team_task_hooks_path(@team), notice: "Hook removed."
  end

  def toggle
    @hook.update!(enabled: !@hook.enabled?)
    redirect_to team_task_hooks_path(@team),
                notice: "Hook #{@hook.enabled? ? 'enabled' : 'disabled'}."
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_hook
    @hook = @team.task_hooks.find(params[:id])
  end

  def hook_params
    params.require(:task_hook).permit(:trigger, :on_status, :skill_id, :agent_id, :enabled)
  end
end
