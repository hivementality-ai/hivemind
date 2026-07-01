# frozen_string_literal: true

class ChannelsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_channel, only: %i[edit update destroy connect connector_health connector_qr connector_logout]

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
      configure_connector(@channel, @credentials)
      process_agent_assignments(params[:agent_assignments].to_unsafe_h) if params[:agent_assignments].present?
      redirect_to channels_path, notice: "#{@channel.name} channel created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def connect
    @connector_url = connector_url_for(@channel)

    # Trigger connection on the connector so it starts generating a QR.
    # Signal links a device via signal-cli; WhatsApp pairs via Baileys.
    begin
      uri = URI("#{@connector_url}#{connector_path(@channel, 'connect')}")
      Net::HTTP.post(uri, "", "Content-Type" => "application/json")
    rescue StandardError => e
      Rails.logger.warn("[Channels] Failed to trigger #{@channel.channel_type} connect: #{e.message}")
    end
  end

  # Proxy health check to connector (browser can't reach Docker network)
  def connector_health
    uri = URI("#{connector_url_for(@channel)}#{connector_path(@channel, 'health')}")
    response = Net::HTTP.get_response(uri)
    render json: response.body, status: response.code.to_i
  rescue StandardError => e
    render json: { status: "unreachable", error: e.message }, status: 503
  end

  # Proxy QR code request to connector
  def connector_qr
    uri = URI("#{connector_url_for(@channel)}#{connector_path(@channel, 'qr')}")
    response = Net::HTTP.get_response(uri)
    render json: response.body, status: response.code.to_i
  rescue StandardError => e
    render json: { status: "error", error: e.message }, status: 503
  end

  # Proxy logout/reconnect request to connector
  def connector_logout
    uri = URI("#{connector_url_for(@channel)}#{connector_path(@channel, 'logout')}")
    response = Net::HTTP.post(uri, "", "Content-Type" => "application/json")
    render json: response.body, status: response.code.to_i
  rescue StandardError => e
    render json: { status: "error", error: e.message }, status: 503
  end

  def update
    @credentials = params[:credentials]&.to_unsafe_h || {}

    if @channel.update(channel_params)
      store_credentials(@credentials) if @credentials.present?
      configure_connector(@channel, @credentials)
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

  def connector_url_for(channel)
    channel.config&.dig("connector_url") || "http://connector:3002"
  end

  # Signal routes its connect/qr/health/logout under the /signal/* namespace
  # on the connector; WhatsApp uses the bare paths.
  def connector_path(channel, action)
    channel.channel_type == "signal" ? "/signal/#{action}" : "/#{action}"
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
    connector_url = channel.config&.dig("connector_url") || "http://connector:3002"

    case channel.channel_type
    when "slack"
      app_token = creds["slack_app_token"].presence || VaultEntry.find_by(namespace: "channel_credentials", key: "slack_app_token")&.value
      bot_token = creds["slack_bot_token"].presence || VaultEntry.find_by(namespace: "channel_credentials", key: "slack_bot_token")&.value
      return unless app_token && bot_token

      Net::HTTP.post(
        URI("#{connector_url}/slack/configure"),
        { app_token: app_token, bot_token: bot_token, channel_id: channel.id }.to_json,
        "Content-Type" => "application/json"
      )
    when "telegram"
      token = creds["telegram_bot_token"].presence || VaultEntry.find_by(namespace: "channel_credentials", key: "telegram_bot_token")&.value
      return unless token

      Net::HTTP.post(
        URI("#{connector_url}/telegram/configure"),
        { bot_token: token, channel_id: channel.id }.to_json,
        "Content-Type" => "application/json"
      )
    when "signal"
      phone = channel.config&.dig("phone_number")
      api_url = channel.config&.dig("signal_api_url") || "http://signal-cli:8080"
      # Note: no phone number is required up front. If the device isn't linked
      # yet, the connector enters linking mode and serves a QR via /signal/qr.

      Net::HTTP.post(
        URI("#{connector_url}/signal/configure"),
        { phone_number: phone, api_url: api_url, channel_id: channel.id }.to_json,
        "Content-Type" => "application/json"
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[Channels] Failed to configure #{channel.channel_type} connector: #{e.message}")
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
