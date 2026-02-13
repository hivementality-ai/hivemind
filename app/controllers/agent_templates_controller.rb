# frozen_string_literal: true

class AgentTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: [:show, :deploy]
  
  def index
    @templates = AgentTemplate.all
    @templates = @templates.by_category(params[:category]) if params[:category].present?
    @templates = @templates.featured if params[:featured] == "true"
    @categories = AgentTemplate::CATEGORIES
  end
  
  def show
  end
  
  def deploy
    response = @template.deploy(
      name: params[:name],
      team: find_team
    )
    
    if response.success?
      redirect_to agent_path(response.data[:agent]), notice: "Agent deployed successfully!"
    else
      redirect_to agent_template_path(@template), alert: response.error
    end
  end
  
  private
  
  def set_template
    @template = AgentTemplate.find(params[:id])
  end
  
  def find_team
    return nil unless params[:team_id].present?
    Team.find(params[:team_id])
  end
end
