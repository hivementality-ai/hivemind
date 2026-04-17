# frozen_string_literal: true

module Tasks
  class TaskHooksController < ApplicationController
    before_action :set_task

    def create
      @hook = @task.task_hooks.build(hook_params)
      @hook.position = @task.task_hooks.count

      if @hook.save
        redirect_to edit_task_path(@task), notice: "Hook added."
      else
        redirect_to edit_task_path(@task), alert: "Failed to add hook: #{@hook.errors.full_messages.to_sentence}."
      end
    end

    def destroy
      hook = @task.task_hooks.find(params[:id])
      hook.destroy!
      redirect_to edit_task_path(@task), notice: "Hook removed."
    rescue ActiveRecord::RecordNotFound
      redirect_to edit_task_path(@task), alert: "Hook not found."
    end

    private

    def set_task
      @task = Task.find(params[:task_id])
    end

    def hook_params
      params.require(:task_hook).permit(:trigger, :on_status, :skill_id)
    end
  end
end
