# frozen_string_literal: true

class TeamsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: %i[edit update destroy export]

  def index
    @teams = Team.includes(agents: :direct_reports).order(:name)
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


  # GET  /teams/:id/export  — show metadata form
  # POST /teams/:id/export  — run export and stream the .swarm.json file
  def export
    @author_name  = export_params[:author_name].presence
    @author_email = export_params[:author_email].presence
    @description  = export_params[:description].presence

    return render :export unless request.post?

    result = Swarms::SwarmExporter.call(
      team:          @team,
      author_name:   @author_name,
      author_email:  @author_email,
      description:   @description,
      strip_secrets: true
    )

    if result.success?
      send_data result.payload[:json],
                filename:    result.payload[:filename],
                type:        "application/json",
                disposition: "attachment"
    else
      flash.now[:alert] = result.message
      render :export, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :description, :custom_soul)
  end

  def export_params
    params.permit(:author_name, :author_email, :description)
  end
end
