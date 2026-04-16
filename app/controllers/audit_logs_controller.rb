# frozen_string_literal: true

class AuditLogsController < ApplicationController
  before_action :authenticate_user!

  ALLOWED_ACTOR_TYPES = %w[agent user system].freeze
  PER_PAGE = 50

  def index
    @logs = AuditLog.recent

    if params[:actor_type].present? && ALLOWED_ACTOR_TYPES.include?(params[:actor_type])
      @logs = @logs.by_actor(params[:actor_type], params[:actor_id]) if params[:actor_id].present?
      @logs = @logs.where(actor_type: params[:actor_type]) if params[:actor_id].blank?
    end

    @logs = @logs.by_action(params[:action_filter]) if params[:action_filter].present?

    if params[:from].present?
      from = Time.zone.parse(params[:from]) rescue nil
      @logs = @logs.where("created_at >= ?", from) if from
    end

    if params[:to].present?
      to = Time.zone.parse(params[:to]) rescue nil
      @logs = @logs.where("created_at <= ?", to.end_of_day) if to
    end

    @total_count = @logs.count
    @page = [params[:page].to_i, 1].max
    @logs = @logs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @total_pages = (@total_count / PER_PAGE.to_f).ceil

    @actor_types = ALLOWED_ACTOR_TYPES
    @distinct_actions = AuditLog.distinct.order(:action).pluck(:action)
  end
end
