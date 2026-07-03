# frozen_string_literal: true

class ToolsController < ApplicationController
  before_action :set_tool, only: [ :show, :edit, :update, :destroy ]

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
    @tool = Tool.new(executor_type: "custom_script", enabled: true)
  end

  def create
    @tool = Tool.new(tool_params)
    parse_parameters_schema
    parse_requirements

    if @tool.save
      redirect_to tools_path, notice: "Tool created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @tool.assign_attributes(tool_params)
    parse_parameters_schema
    parse_requirements

    if @tool.save
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
    params.require(:tool).permit(:name, :description, :executor_type, :enabled, :requires_approval, :script_template)
  end

  def parse_parameters_schema
    json_str = params.dig(:tool, :parameters_schema_json).to_s.strip
    return if json_str.empty?

    begin
      @tool.parameters_schema = JSON.parse(json_str)
    rescue JSON::ParserError => e
      @tool.errors.add(:parameters_schema, "is not valid JSON: #{e.message}")
    end
  end

  def parse_requirements
    json_str = params.dig(:tool, :requirements_json).to_s.strip
    return if json_str.empty?

    begin
      @tool.requirements = JSON.parse(json_str)
    rescue JSON::ParserError => e
      @tool.errors.add(:requirements, "is not valid JSON: #{e.message}")
    end
  end
end
