# frozen_string_literal: true

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :find_channel
  before_action :verify_webhook_signature

  def receive
    adapter = get_adapter(@channel)
    
    return render json: { error: "Unsupported channel type" }, status: :unprocessable_entity unless adapter

    result = adapter.receive(webhook_params)

    if result.success?
      # Handle Slack URL verification challenge
      if result.data[:challenge]
        render json: { challenge: result.data[:challenge] }
      else
        render json: { status: "received" }, status: :ok
      end
    else
      Rails.logger.error("Webhook processing failed: #{result.error}")
      render json: { error: result.error }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("Webhook error: #{e.message}")
    render json: { error: "Internal server error" }, status: :internal_server_error
  ensure
    # Audit log all webhook attempts
    AuditLog.create(
      actor_type: "System",
      action: "webhook_received",
      resource_type: "Channel",
      resource_id: @channel&.id,
      metadata: {
        channel_type: params[:channel_type],
        verified: @webhook_verified,
        ip: request.remote_ip
      }
    )
  end

  private

  def find_channel
    @channel = Channel.find_by(channel_type: params[:channel_type])
    
    unless @channel
      render json: { error: "Channel not found" }, status: :not_found
    end
  end

  def verify_webhook_signature
    adapter = get_adapter(@channel)
    @webhook_verified = adapter&.verify_webhook(request)

    unless @webhook_verified
      Rails.logger.warn("Webhook verification failed for #{params[:channel_type]}")
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def get_adapter(channel)
    return nil unless channel

    case channel.channel_type
    when "telegram"
      Channels::TelegramAdapter.new(channel)
    when "discord"
      Channels::DiscordAdapter.new(channel)
    when "slack"
      Channels::SlackAdapter.new(channel)
    else
      nil
    end
  end

  def webhook_params
    params.permit!.to_h.except(:controller, :action, :channel_type)
  end
end
