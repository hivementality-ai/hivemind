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
      configure_connector(@channel, @credentials) if @credentials.present?
      process_agent_assignments(params[:agent_assignments].to_unsafe_h) if params[:agent_assignments].present?
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
      configure_connector(@channel, @credentials) if @credentials.present?
      process_agent_assignments(params[:agent_assignments].to_unsafe_h) if params[:agent_assignments].present?
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
    permitted = params.require(:channel).permit(:name, :channel_type, :enabled, config: {})
    if params[:channel][:routing_rules].present?
      rules = params[:channel][:routing_rules].map do |rule|
        { "pattern" => rule[:pattern].to_s.strip, "agent_id" => rule[:agent_id].to_i }
      end.reject { |r| r["pattern"].blank? || r["agent_id"].zero? }
      permitted[:routing_rules] = rules
    end
    permitted
  end

  def configure_connector(channel, creds)
    return unless channel.channel_type == "slack"

    app_token = creds["slack_app_token"].presence || VaultEntry.find_by(namespace: "channel_credentials", key: "slack_app_token")&.value
    bot_token = creds["slack_bot_token"].presence || VaultEntry.find_by(namespace: "channel_credentials", key: "slack_bot_token")&.value
    return unless app_token && bot_token

    connector_url = channel.config&.dig("connector_url") || "http://connector:3002"

    Net::HTTP.post(
      URI("#{connector_url}/slack/configure"),
      { app_token: app_token, bot_token: bot_token, channel_id: channel.id }.to_json,
      "Content-Type" => "application/json"
    )
  rescue StandardError => e
    Rails.logger.warn("[Channels] Failed to configure Slack connector: #{e.message}")
  end

  def store_credentials(creds)
    creds.each do |key, value|
      next if value.blank?

      entry = VaultEntry.find_or_initialize_by(
        namespace: "channel_credentials",
        key: key
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
