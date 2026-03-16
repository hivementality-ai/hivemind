# frozen_string_literal: true

class ScheduledTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_task, only: %i[edit update toggle destroy run_now]

  def index
    @tasks = ScheduledTask.includes(:agent).order(created_at: :desc)
    @agents = Agent.visible.order(:name)

    if params[:agent_id].present?
      @tasks = @tasks.where(agent_id: params[:agent_id])
    end

    if params[:status].present?
      case params[:status]
      when "active" then @tasks = @tasks.active.enabled
      when "paused" then @tasks = @tasks.where(confirmation_status: "paused").or(@tasks.disabled)
      when "pending" then @tasks = @tasks.pending_confirmation
      end
    end
  end

  def edit
    @agents = Agent.visible.order(:name)
  end

  def update
    old_agent = @task.agent

    if @task.update(task_params)
      # Re-sync sidekiq if agent or schedule changed
      Agents::ManageCron.new(agent: old_agent).send(:remove_from_sidekiq, @task) if old_agent.id != @task.agent_id
      Agents::ManageCron.new(agent: @task.agent).send(:sync_to_sidekiq, @task) if @task.enabled?
      redirect_to scheduled_tasks_path, notice: "#{@task.name} updated"
    else
      @agents = Agent.visible.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle
    if @task.enabled?
      @task.update!(enabled: false, confirmation_status: "paused")
      Agents::ManageCron.new(agent: @task.agent).send(:remove_from_sidekiq, @task)
      notice = "#{@task.name} paused"
    else
      @task.update!(enabled: true, confirmation_status: "active")
      Agents::ManageCron.new(agent: @task.agent).send(:sync_to_sidekiq, @task)
      notice = "#{@task.name} resumed"
    end
    redirect_to scheduled_tasks_path, notice: notice
  end

  def destroy
    name = @task.name
    Agents::ManageCron.new(agent: @task.agent).send(:remove_from_sidekiq, @task)
    @task.destroy!
    redirect_to scheduled_tasks_path, notice: "#{name} deleted"
  end

  def run_now
    if @task.job_class == "ScheduledScriptJob"
      ScheduledScriptJob.perform_later(@task.id)
    else
      ScheduledAgentJob.perform_later(@task.id)
    end
    @task.touch(:last_run_at)
    redirect_to scheduled_tasks_path, notice: "#{@task.name} triggered"
  end

  private

  def set_task
    @task = ScheduledTask.find(params[:id])
  end

  def task_params
    permitted = params.require(:scheduled_task).permit(:name, :agent_id, :schedule, :description)
    if params[:scheduled_task][:prompt].present?
      permitted[:job_params] = (@task.job_params || {}).merge("prompt" => params[:scheduled_task][:prompt])
    end
    permitted
  end
end
