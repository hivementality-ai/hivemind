# frozen_string_literal: true

class ToolsController < ApplicationController
  before_action :set_tool, only: [:show, :edit, :update, :destroy]

  def index
    @tools = Tool.order(:name)
    @recent_executions = ToolExecution.includes(:tool, :agent, :session)
                                     .order(created_at: :desc)
                                     .limit(20)
  end

  def show
    @executions = @tool.tool_executions
                       .includes(:agent, :session)
                       .order(created_at: :desc)
                       .limit(50)
  end

  def new
    @tool = Tool.new
  end

  def create
    @tool = Tool.new(tool_params)
    if @tool.save
      redirect_to tools_path, notice: "Tool created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @tool.update(tool_params)
      redirect_to tools_path, notice: "Tool updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tool.destroy
    redirect_to tools_path, notice: "Tool deleted"
  end

  private

  def set_tool
    @tool = Tool.find(params[:id])
  end

  def tool_params
    params.require(:tool).permit(:name, :description, :executor_type, :enabled, :requires_approval)
  end
end
