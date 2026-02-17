# frozen_string_literal: true

class AgentChannelsController < ApplicationController
  before_action :find_channel
  before_action :find_agent_channel, only: [ :update, :destroy ]

  def create
    @agent_channel = @channel.agent_channels.build(agent_channel_params)

    if @agent_channel.save
      redirect_to edit_channel_path(@channel), notice: "Agent bot configured successfully"
    else
      redirect_to edit_channel_path(@channel), alert: "Failed to configure agent bot: #{@agent_channel.errors.full_messages.join(', ')}"
    end
  end

  def update
    if @agent_channel.update(agent_channel_params)
      redirect_to edit_channel_path(@channel), notice: "Agent bot updated successfully"
    else
      redirect_to edit_channel_path(@channel), alert: "Failed to update agent bot: #{@agent_channel.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    @agent_channel.destroy!
    redirect_to edit_channel_path(@channel), notice: "Agent bot removed successfully"
  rescue StandardError => e
    redirect_to edit_channel_path(@channel), alert: "Failed to remove agent bot: #{e.message}"
  end

  private

  def find_channel
    @channel = Channel.find(params[:channel_id])
  end

  def find_agent_channel
    @agent_channel = @channel.agent_channels.find(params[:id])
  end

  def agent_channel_params
    params.require(:agent_channel).permit(
      :agent_id,
      :is_default,
      :bot_token,
      config: {}
    )
  end
end
