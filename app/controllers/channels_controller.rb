# frozen_string_literal: true

class ChannelsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_channel, only: %i[edit update destroy connect]

  def index
    @channels = Channel.order(:name)
  end

  def new
    @channel = Channel.new
  end

  def create
    @channel = Channel.new(channel_params)
    @credentials = params[:credentials]&.to_unsafe_h || {}

    if @channel.save
      store_credentials(@credentials) if @credentials.present?
      redirect_to channels_path, notice: "#{@channel.name} channel created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def connect
    @connector_url = @channel.config&.dig("connector_url") || "http://localhost:3002"
  end

  def update
    @credentials = params[:credentials]&.to_unsafe_h || {}

    if @channel.update(channel_params)
      store_credentials(@credentials) if @credentials.present?
      process_agent_assignments(params[:agent_assignments]) if params[:agent_assignments].present?
      redirect_to channels_path, notice: "#{@channel.name} updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @channel.destroy
    redirect_to channels_path, notice: "Channel removed"
  end

  private

  def set_channel
    @channel = Channel.find(params[:id])
  end

  def channel_params
    params.require(:channel).permit(:name, :channel_type, :enabled, config: {})
  end

  def store_credentials(creds)
    creds.each do |key, value|
      next if value.blank?

      entry = VaultEntry.find_or_initialize_by(
        namespace: "channel_credentials",
        key: "#{@channel.channel_type}_#{key}"
      )
      entry.value = value
      entry.save!
    end
  end

  def process_agent_assignments(assignments)
    default_agent_id = params[:default_agent]&.to_i

    assignments.each do |agent_id, assignment_data|
      agent_id = agent_id.to_i
      agent = Agent.find_by(id: agent_id)
      next unless agent

      enabled = assignment_data[:enabled] == "1"

      if enabled
        # Create or update agent channel
        agent_channel = @channel.agent_channels.find_or_initialize_by(agent: agent)
        agent_channel.is_default = (default_agent_id == agent_id)

        # Set bot token if provided
        if assignment_data[:bot_token].present?
          agent_channel.bot_token = assignment_data[:bot_token]
        end

        agent_channel.save!
      else
        # Remove agent channel if exists
        @channel.agent_channels.find_by(agent: agent)&.destroy
      end
    end
  end
end
