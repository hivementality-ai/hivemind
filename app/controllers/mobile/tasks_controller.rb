# frozen_string_literal: true

module Mobile
  class TasksController < BaseController
    # Most-relevant-first: what's being worked on before the backlog.
    DISPLAY_ORDER = %w[in_progress review todo backlog done].freeze

    def index
      @tasks_by_status = DISPLAY_ORDER.index_with do |status|
        Task.not_archived.by_status(status).by_priority
            .includes(:assigned_to_agent, :project)
            .to_a
      end
      @total_open = Task.not_archived.open.count
      @total_done = Task.not_archived.done.count
    end

    def show
      @task   = Task.includes(:assigned_to_agent, :created_by_agent, :project).find(params[:id])
      @events = @task.task_events.recent_first.includes(:agent).limit(20)
    end
  end
end
