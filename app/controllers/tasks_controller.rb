# frozen_string_literal: true

class TasksController < ApplicationController
  before_action :set_task, only: [ :show, :edit, :update, :destroy, :move ]

  def index
    @tasks_by_status = Task::STATUSES.index_with do |status|
      Task.by_status(status).by_priority.includes(:assigned_to_agent, :created_by_agent).to_a
    end
    @agents = Agent.visible.enabled.order(:name)
    @total_open  = Task.open.count
    @total_done  = Task.done.count
  end

  def show
    @agents = Agent.visible.enabled.order(:name)
  end

  def new
    @task = Task.new(status: "backlog", priority: "medium")
    @agents = Agent.visible.enabled.order(:name)
  end

  def create
    @task = Task.new(task_params)

    if @task.save
      redirect_to tasks_path, notice: "Task created."
    else
      @agents = Agent.visible.enabled.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @agents = Agent.visible.enabled.order(:name)
  end

  def update
    # Handle inline comment submission from the show page
    if params[:task] && params[:task][:_comment_body].present?
      @task.add_comment(author_name: "You", body: params[:task][:_comment_body])
      redirect_to task_path(@task), notice: "Comment added."
      return
    end

    if @task.update(task_params)
      respond_to do |format|
        format.html { redirect_to tasks_path, notice: "Task updated." }
        format.json { render json: { status: "ok", task: task_json(@task) } }
      end
    else
      respond_to do |format|
        format.html do
          @agents = Agent.visible.enabled.order(:name)
          render :edit, status: :unprocessable_entity
        end
        format.json { render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @task.destroy
    redirect_to tasks_path, notice: "Task deleted."
  end

  # PATCH /tasks/:id/move  — drag-and-drop status update (JSON)
  def move
    new_status = params[:status].to_s.strip

    unless Task::STATUSES.include?(new_status)
      render json: { error: "Invalid status" }, status: :unprocessable_entity
      return
    end

    @task.update!(status: new_status)
    render json: { status: "ok", task: task_json(@task) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_task
    @task = Task.find(params[:id])
  end

  def task_params
    params.require(:task).permit(
      :title,
      :description,
      :status,
      :priority,
      :assigned_to_agent_id,
      :due_at
    )
  end

  def task_json(task)
    {
      id:                   task.id,
      title:                task.title,
      status:               task.status,
      priority:             task.priority,
      assigned_to_agent_id: task.assigned_to_agent_id,
      due_at:               task.due_at&.iso8601
    }
  end
end
