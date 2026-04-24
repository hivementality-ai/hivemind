# frozen_string_literal: true

class HeartbeatsController < ApplicationController
  before_action :authenticate_user!

  def index
    @config = heartbeat_config
    @runs = HeartbeatRun.includes(:agent, :session).recent
    @provider_models = enabled_provider_models
    @soul_agent = Agent.system_assistant
    @heartbeat_memory = @soul_agent.memory_entries.order(updated_at: :desc).first
  end

  def update
    settings = {
      "enabled" => params[:enabled] == "1",
      "model" => params[:model].presence,
      "provider" => params[:provider].presence,
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

  def update_soul
    agent = Agent.system_assistant
    agent.update!(system_prompt: params[:system_prompt].to_s.strip)
    redirect_to heartbeats_path, notice: "Soul updated"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to heartbeats_path, alert: "Failed to update soul: #{e.message}"
  end

  def clear_memories
    agent = Agent.system_assistant
    count = agent.memory_entries.count
    agent.memory_entries.destroy_all
    redirect_to heartbeats_path, notice: "Cleared #{count} heartbeat #{"memory".pluralize(count)}"
  end

  def add_standing_task
    task_name = params[:task].to_s.strip
    return redirect_to heartbeats_path, alert: "Task cannot be blank" if task_name.blank?

    setting = Setting.find_or_create_by!(key: "heartbeat_tasks") { |s| s.value = "[]" }

    setting.with_lock do
      tasks = begin
        JSON.parse(setting.reload.value || "[]")
      rescue JSON::ParserError
        []
      end

      if tasks.any? { |t| t["task"] == task_name && t["protected"] == true }
        return redirect_to heartbeats_path, alert: "That standing task already exists"
      end

      tasks << {
        "task" => task_name,
        "protected" => true,
        "added_by" => current_user.email,
        "added_at" => Time.current.iso8601
      }

      setting.update!(value: tasks.to_json)
    end

    redirect_to heartbeats_path, notice: "Standing task added"
  end

  def delete_standing_task
    task_name = params[:task].to_s.strip
    return redirect_to heartbeats_path, alert: "No task specified" if task_name.blank?

    setting = Setting.find_or_create_by!(key: "heartbeat_tasks") { |s| s.value = "[]" }
    removed = 0

    setting.with_lock do
      tasks = begin
        JSON.parse(setting.reload.value || "[]")
      rescue JSON::ParserError
        []
      end

      before = tasks.size
      tasks.reject! { |t| t["task"] == task_name && t["protected"] == true }
      removed = before - tasks.size
      setting.update!(value: tasks.to_json)
    end

    if removed > 0
      redirect_to heartbeats_path, notice: "Standing item deleted"
    else
      redirect_to heartbeats_path, alert: "Standing item not found"
    end
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
    { "enabled" => false, "model" => nil, "provider" => nil, "interval_minutes" => 30, "prompt" => nil, "light_context" => false }
  end

  def load_tasks
    raw = Setting.get("heartbeat_tasks")
    return [] unless raw
    JSON.parse(raw)
  rescue JSON::ParserError
    []
  end

  # Returns an array of { provider_name:, adapter_type:, models: [{id:, name:}] }
  # for all enabled providers that have at least one model configured.
  def enabled_provider_models
    ProviderConfig.enabled_providers.filter_map do |pc|
      models = (pc.model_definitions || []).map { |m| { id: m["id"], name: m["id"] } }
      next if models.empty?

      { provider_name: pc.name, adapter_type: pc.adapter_type, models: models }
    end
  end
end
