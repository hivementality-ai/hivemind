# frozen_string_literal: true

class TasksController < ApplicationController
  before_action :set_task, only: [ :show, :edit, :update, :destroy ]
  before_action :set_teams_and_agents, only: [ :index, :new, :edit, :create ]

  # GET /tasks
  def index
    @team = if params[:team_id].present?
      Team.find_by(id: params[:team_id]) || Team.first
    else
      Team.first
    end

    scope = @team ? @team.tasks.includes(:agent, :session) : Task.none

    if params[:agent_slug].present?
      agent = Agent.find_by(slug: params[:agent_slug])
      scope = scope.assigned_to(agent) if agent
    end

    @tasks_by_status = Task.statuses.keys.index_with do |status_key|
      scope.by_status(status_key).order(priority: :desc, created_at: :desc)
    end

    @selected_team_id = @team&.id
    @selected_agent_slug = params[:agent_slug]
  end

  # GET /tasks/:id
  def show
    @linked_session = @task.session
    @agent = @task.agent
  end

  # GET /tasks/new
  def new
    @task = Task.new(team: @teams.first)
  end

  # GET /tasks/:id/edit
  def edit
  end

  # POST /tasks
  def create
    @task = Task.new(task_params)
    @task.created_by = "user"

    respond_to do |format|
      if @task.save
        format.html { redirect_to task_path(@task), notice: "Task created." }
        format.turbo_stream
        format.json { render json: @task, status: :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /tasks/:id
  def update
    respond_to do |format|
      if @task.update(task_params)
        format.html { redirect_to task_path(@task), notice: "Task updated." }
        format.turbo_stream
        format.json { render json: @task }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /tasks/:id
  def destroy
    team_id = @task.team_id
    @task.destroy
    respond_to do |format|
      format.html { redirect_to tasks_path(team_id: team_id), notice: "Task deleted." }
      format.json { head :no_content }
    end
  end

  private

  def set_task
    @task = Task.find(params[:id])
  end

  def set_teams_and_agents
    @teams = Team.order(:name)
    selected_team = if params[:team_id].present?
      Team.find_by(id: params[:team_id])
    else
      @teams.first
    end
    @agents = selected_team ? selected_team.agents.enabled.order(:name) : Agent.none
  end

  def task_params
    params.require(:task).permit(:title, :description, :status, :priority, :agent_id, :team_id, :session_id, :due_date)
  end
end
