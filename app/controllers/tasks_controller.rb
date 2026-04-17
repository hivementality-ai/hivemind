# frozen_string_literal: true

class TasksController < ApplicationController
  before_action :set_task, only: [ :show, :edit, :update, :destroy, :move, :toggle_checklist, :archive ]

  def index
    @tasks_by_status = Task::STATUSES.index_with do |status|
      Task.not_archived.by_status(status).by_priority
          .includes(:assigned_to_agent, :created_by_agent, :project, :project_milestone, :task_attachments)
          .to_a
    end
    @agents          = Agent.visible.enabled.order(:name)
    @total_open      = Task.not_archived.open.count
    @total_done      = Task.not_archived.done.count
    @total_archived  = Task.archived.count
  end

  def show
    @agents     = Agent.visible.enabled.order(:name)
    @projects   = Project.order(:title)
    @milestones = @task.project ? @task.project.milestones.ordered : ProjectMilestone.none
    @events     = @task.task_events.recent_first.limit(20)
  end

  def new
    @task       = Task.new(status: "backlog", priority: "medium")
    @agents     = Agent.visible.enabled.order(:name)
    @templates  = TaskTemplate.order(:name)
    @projects   = Project.order(:title)
    @milestones = ProjectMilestone.none
  end

  def create
    @task = Task.new(task_params)

    if params[:task][:task_template_id].present?
      template = TaskTemplate.find_by(id: params[:task][:task_template_id])
      @task.apply_template!(template) if template
    end

    if @task.save
      Tasks::EventLogger.call(task: @task, event_type: "created", summary: "Task created: #{@task.title}")
      redirect_to tasks_path, notice: "Task created."
    else
      @agents     = Agent.visible.enabled.order(:name)
      @templates  = TaskTemplate.order(:name)
      @projects   = Project.order(:title)
      @milestones = @task.project ? @task.project.milestones.ordered : ProjectMilestone.none
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @agents     = Agent.visible.enabled.order(:name)
    @templates  = TaskTemplate.order(:name)
    @projects   = Project.order(:title)
    @milestones = @task.project ? @task.project.milestones.ordered : ProjectMilestone.none
  end

  def update
    # Handle inline comment submission from the show page
    if params[:task] && params[:task][:_comment_body].present?
      @task.add_comment(author_name: "You", body: params[:task][:_comment_body])
      Tasks::EventLogger.call(task: @task, event_type: "comment_added", summary: "Comment added")
      redirect_to task_path(@task), notice: "Comment added."
      return
    end

    old_status = @task.status
    new_status = task_params[:status]

    # Route status changes through TransitionService
    if new_status.present? && new_status != old_status
      result = Tasks::TransitionService.call(task: @task, new_status: new_status)
      unless result.success?
        respond_to do |format|
          format.html do
            flash[:alert] = result.error
            @agents     = Agent.visible.enabled.order(:name)
            @templates  = TaskTemplate.order(:name)
            @projects   = Project.order(:title)
            @milestones = @task.project ? @task.project.milestones.ordered : ProjectMilestone.none
            render :edit, status: :unprocessable_entity
          end
          format.json { render json: { error: result.error }, status: :unprocessable_entity }
        end
        return
      end
      # Update other fields (excluding status which TransitionService already handled)
      other_params = task_params.except(:status)
      @task.update!(other_params) if other_params.any?
    elsif @task.update(task_params)
      # No status change — normal update
    else
      respond_to do |format|
        format.html do
          @agents     = Agent.visible.enabled.order(:name)
          @templates  = TaskTemplate.order(:name)
          @projects   = Project.order(:title)
          @milestones = @task.project ? @task.project.milestones.ordered : ProjectMilestone.none
          render :edit, status: :unprocessable_entity
        end
        format.json { render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity }
      end
      return
    end

    respond_to do |format|
      format.html { redirect_to tasks_path, notice: "Task updated." }
      format.json { render json: { status: "ok", task: task_json(@task) } }
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

    result = Tasks::TransitionService.call(task: @task, new_status: new_status)
    unless result.success?
      render json: { error: result.error }, status: :unprocessable_entity
      return
    end

    render json: { status: "ok", task: task_json(@task.reload) }
  end

  # PATCH /tasks/:id/archive — archive a completed task
  def archive
    unless @task.status == "done"
      respond_to do |format|
        format.html { redirect_to tasks_path, alert: "Only completed tasks can be archived." }
        format.json { render json: { error: "task must be in done status" }, status: :unprocessable_entity }
      end
      return
    end

    @task.archive!
    Tasks::EventLogger.call(task: @task, event_type: "archived", summary: "Task archived")

    respond_to do |format|
      format.html { redirect_to tasks_path, notice: "Task archived." }
      format.json { render json: { status: "ok" } }
    end
  end

  # PATCH /tasks/:id/toggle_checklist — toggle a checklist item
  def toggle_checklist
    index = params[:index].to_i

    if @task.toggle_checklist_item(index)
      Tasks::EventLogger.call(
        task: @task, event_type: "checklist_updated",
        summary: "Checklist item toggled: #{@task.checklist[index]['title']}"
      )
      respond_to do |format|
        format.html { redirect_to task_path(@task) }
        format.json { render json: { status: "ok", checklist: @task.checklist } }
      end
    else
      respond_to do |format|
        format.html { redirect_to task_path(@task), alert: "Invalid checklist item." }
        format.json { render json: { error: "Invalid index" }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_task
    @task = Task.includes(:task_attachments).find(params[:id])
  end

  def task_params
    params.require(:task).permit(
      :title,
      :description,
      :status,
      :priority,
      :assigned_to_agent_id,
      :task_template_id,
      :project_id,
      :project_milestone_id,
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
