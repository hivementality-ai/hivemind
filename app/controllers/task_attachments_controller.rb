# frozen_string_literal: true

class TaskAttachmentsController < ApplicationController
  before_action :set_task,       only: [ :create ]
  before_action :set_attachment, only: [ :destroy ]

  def create
    @attachment = @task.task_attachments.build(attachment_params)
    @attachment.uploaded_by = current_user&.email || "user"

    if @attachment.save
      Tasks::EventLogger.call(
        task:       @task,
        event_type: "attachment_added",
        summary:    "Attachment added: #{@attachment.title}"
      )
      redirect_to task_path(@task), notice: "Attachment added."
    else
      redirect_to task_path(@task), alert: @attachment.errors.full_messages.to_sentence
    end
  end

  def destroy
    task  = @attachment.task
    title = @attachment.title

    ActiveRecord::Base.transaction do
      @attachment.destroy!
      Tasks::EventLogger.call(
        task:       task,
        event_type: "attachment_removed",
        summary:    "Attachment removed: #{title}"
      )
    end

    redirect_to task_path(task), notice: "Attachment removed."
  end

  private

  def set_task
    @task = Task.find(params[:task_id])
  end

  def set_attachment
    @attachment = TaskAttachment.find(params[:id])
  end

  def attachment_params
    params.require(:task_attachment).permit(:title, :url)
  end
end
