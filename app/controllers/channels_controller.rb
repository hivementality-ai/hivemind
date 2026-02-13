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

    # Store credentials in vault if provided
    store_credentials(params[:credentials]) if params[:credentials].present?

    if @channel.save
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
    store_credentials(params[:credentials]) if params[:credentials].present?

    if @channel.update(channel_params)
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
end
