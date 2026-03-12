# frozen_string_literal: true

class PluginsController < ApplicationController
  def index
    @plugins = Plugins::Registry.loaded
  end

  def show
    @plugin = Plugins::Registry.find(params[:id])
    redirect_to plugins_path, alert: "Plugin not found" unless @plugin
  end

  def enable
    result = Plugins::Registry.enable(params[:id])
    if result.success?
      redirect_to plugins_path, notice: "Plugin '#{params[:id]}' enabled"
    else
      redirect_to plugins_path, alert: result.error
    end
  end

  def disable
    result = Plugins::Registry.disable(params[:id])
    if result.success?
      redirect_to plugins_path, notice: "Plugin '#{params[:id]}' disabled"
    else
      redirect_to plugins_path, alert: result.error
    end
  end
end
