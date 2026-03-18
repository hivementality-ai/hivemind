# frozen_string_literal: true

class TeamsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: %i[edit update destroy]

  def index
    @teams = Team.includes(:agents).order(:name)
  end

  def new
    @team = Team.new
  end

  def create
    @team = Team.new(team_params)

    if @team.save
      redirect_to teams_path, notice: "#{@team.name} created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @team.update(team_params)
      redirect_to teams_path, notice: "#{@team.name} updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @team.name
    @team.destroy
    redirect_to teams_path, notice: "#{name} deleted"
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :description, :custom_soul)
  end
end
