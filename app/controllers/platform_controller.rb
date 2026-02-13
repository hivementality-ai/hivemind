# frozen_string_literal: true

class PlatformController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!, except: [:status]
  
  def status
    response = Platform::ContainerStatus.call
    
    if response.success?
      @services = response.data[:services]
    else
      flash.now[:alert] = response.error
      @services = []
    end
  end
  
  def restart
    service_name = params[:service]
    
    response = Platform::RestartService.call(
      service_name: service_name,
      actor: current_user.email
    )
    
    if response.success?
      redirect_to platform_status_path, notice: "#{service_name} restarted successfully"
    else
      redirect_to platform_status_path, alert: response.error
    end
  end
  
  def clear_cache
    response = Platform::ClearCache.call(
      cache_type: params[:cache_type] || "all",
      actor: current_user.email
    )
    
    if response.success?
      redirect_to platform_status_path, notice: "Cache cleared successfully"
    else
      redirect_to platform_status_path, alert: response.error
    end
  end
  
  private
  
  def require_admin!
    unless current_user.admin?
      redirect_to root_path, alert: "Admin access required"
    end
  end
end
