# frozen_string_literal: true

class HeartbeatsController < ApplicationController
  before_action :authenticate_user!

  def index
    @config = heartbeat_config
    @runs = HeartbeatRun.includes(:agent, :session).recent
  end

  def update
    settings = {
      "enabled" => params[:enabled] == "1",
      "model" => params[:model].presence,
      "interval_minutes" => params[:interval_minutes].to_i.clamp(5, 1440),
      "prompt" => params[:prompt].presence,
      "light_context" => params[:light_context] == "1"
    }

    Setting.set("heartbeat", settings.to_json)
    redirect_to heartbeats_path, notice: "Heartbeat settings saved"
  end

  def trigger
    HeartbeatJob.perform_later
    redirect_to heartbeats_path, notice: "Heartbeat triggered"
  end

  private

  def heartbeat_config
    raw = Setting.get("heartbeat")
    return default_config unless raw
    JSON.parse(raw)
  rescue JSON::ParserError
    default_config
  end

  def default_config
    { "enabled" => false, "model" => "llama3.2:3b", "interval_minutes" => 30, "prompt" => nil, "light_context" => false }
  end
end
