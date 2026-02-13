# frozen_string_literal: true

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  before_action :find_channel
  before_action :verify_webhook_signature

  # GET for webhook verification (Telegram, WhatsApp)
  def verify
    # WhatsApp/Meta webhook verification
    if params["hub.mode"] == "subscribe" && params["hub.verify_token"] == @channel.config&.dig("verify_token")
      render plain: params["hub.challenge"], status: :ok
    else
      render plain: "Forbidden", status: :forbidden
    end
  end

  # POST for incoming messages
  def receive
    adapter = Channels::Registry.adapter_for(@channel)
    result = adapter.receive(webhook_params)

    if result.success?
      # Slack URL verification challenge
      if result.data[:challenge]
        render json: { challenge: result.data[:challenge] }
        return
      end

      # Route inbound message to agent if present
      if result.data[:inbound_message]
        InboundMessageJob.perform_later(result.data[:inbound_message].id)
      end

      render json: { status: "ok" }, status: :ok
    else
      Rails.logger.error("Webhook processing failed: #{result.error}")
      render json: { error: result.error }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("Webhook error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { error: "Internal server error" }, status: :internal_server_error
  end

  private

  def find_channel
    @channel = Channel.find_by(channel_type: params[:channel_type], enabled: true)
    render json: { error: "Channel not found" }, status: :not_found unless @channel
  end

  def verify_webhook_signature
    adapter = Channels::Registry.adapter_for(@channel)
    unless adapter.verify_webhook(request)
      Rails.logger.warn("Webhook verification failed for #{params[:channel_type]} from #{request.remote_ip}")
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def webhook_params
    params.permit!.to_h.except(:controller, :action, :channel_type)
  end
end
