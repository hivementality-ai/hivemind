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

      # Discord PING/PONG interaction verification
      if result.data[:pong]
        render json: { type: 1 }
        return
      end

      # Discord interaction response (ACK)
      if result.data[:interaction]
        inbound = result.data[:inbound_message]
        command = inbound&.content.to_s

        if command.match?(/^\/(?:help|status|ping|info)\b/)
          # Respond immediately with ephemeral message for simple info commands
          render json: {
            type: 4, # CHANNEL_MESSAGE_WITH_SOURCE
            data: {
              content: ephemeral_interaction_response(command),
              flags: 64 # EPHEMERAL - only visible to the invoking user
            }
          }
        else
          # Defer response for commands that need agent processing
          render json: { type: 5 } # DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE
        end
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

  def ephemeral_interaction_response(command)
    case command
    when /^\/ping/
      "🏓 Pong! Hivemind is online."
    when /^\/status/
      agents = Agent.visible.enabled
      agent_list = agents.map { |a| "• **#{a.name}** — #{a.role}" }.join("\n")
      "📊 **Hivemind Status**\n\n**Agents online:** #{agents.count}\n#{agent_list}"
    when /^\/help/
      "🐝 **Hivemind Help**\n\n" \
        "Just @ mention an agent to talk to them!\n" \
        "Available commands:\n" \
        "• `/ping` — Check if Hivemind is online\n" \
        "• `/status` — See active agents\n" \
        "• `/help` — Show this message"
    when /^\/info/
      "ℹ️ **Hivemind** — Multi-agent AI platform\nVersion: #{Rails.application.config.respond_to?(:version) ? Rails.application.config.version : '1.0'}"
    else
      "Command received. Processing..."
    end
  end

  def webhook_params
    # Webhooks have arbitrary payloads from external platforms — permit all keys intentionally
    params.to_unsafe_h.except(:controller, :action, :channel_type) # brakeman:ignore:MassAssignment
  end
end
