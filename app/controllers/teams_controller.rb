# frozen_string_literal: true

class TeamsController < ApplicationController
  before_action :set_team, only: [ :edit, :update ]

  def edit
  end

  def update
    if @team.update(team_params)
      redirect_to edit_team_path(@team), notice: "Team updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :description, :custom_soul)
  end
end
