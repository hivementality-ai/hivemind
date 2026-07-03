# frozen_string_literal: true

# User-facing management of outbound webhook subscriptions.
#
# Security model:
#   - Admin/owner only (same gate as VaultEntriesController).
#   - Secret is generated server-side on create; shown ONCE in the flash notice,
#     never rendered again (stored encrypted via ActiveRecord::Encryption).
class WebhookEndpointsController < ApplicationController
  before_action :authorize_admin_or_owner!
  before_action :set_endpoint, only: [ :edit, :update, :destroy ]

  def index
    @endpoints = WebhookEndpoint.order(:created_at)
  end

  def new
    @endpoint = WebhookEndpoint.new(event_types: [], enabled: true)
  end

  def create
    @endpoint = WebhookEndpoint.new(endpoint_params)
    if @endpoint.save
      redirect_to webhook_endpoints_path,
        notice: "Webhook created. Secret (copy now — not shown again): #{@endpoint.secret}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @endpoint.update(endpoint_params)
      redirect_to webhook_endpoints_path, notice: "Webhook updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @endpoint.destroy!
    redirect_to webhook_endpoints_path, notice: "Webhook deleted."
  end

  private

  def set_endpoint
    @endpoint = WebhookEndpoint.find(params[:id])
  end

  def endpoint_params
    params.require(:webhook_endpoint)
          .permit(:url, :enabled, event_types: [])
          .tap { |p| p[:event_types] = Array(p[:event_types]).reject(&:blank?) }
  end
end
