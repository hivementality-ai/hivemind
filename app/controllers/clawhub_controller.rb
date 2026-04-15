# frozen_string_literal: true

class ClawhubController < ApplicationController
  before_action :authenticate_user!

  PENDING_INSTALL_TTL = 30.minutes

  def index
    @sort = params[:sort].presence || "trending"
    @query = params[:q].presence

    if @query
      result = client.search_skills(query: @query, limit: 20)
      @skills = result["results"] || []
    else
      result = client.list_skills(sort: @sort, cursor: params[:cursor])
      @skills = result["items"] || []
      @next_cursor = result["nextCursor"]
    end

    @installed_urls = Skill.where(source: "clawhub").pluck(:source_url).to_set

    if turbo_frame_request?
      render partial: "clawhub/results", locals: { skills: @skills, installed_urls: @installed_urls, next_cursor: @next_cursor, sort: @sort }
    end
  rescue ClawHub::ApiError => e
    @skills = []
    @error = e.message
  end

  def show
    @slug = params[:slug]
    @skill_data = client.get_skill(slug: @slug)
    @installed = Skill.exists?(source: "clawhub", source_url: "#{ClawHub::Client::BASE_URL}/skills/#{@slug}")
  rescue ClawHub::ApiError => e
    redirect_to clawhub_index_path, alert: "Could not load skill: #{e.message}"
  end

  def install
    slug = params[:slug]
    result = ClawHub::SkillInstaller.call(slug: slug, user: current_user)

    unless result.success?
      redirect_to clawhub_path(slug: slug), alert: result.error
      return
    end

    case result.data[:status]
    when "installed"
      redirect_to skill_path(result.data[:skill]), notice: "#{result.data[:skill].name} installed from ClawHub"
    when "pending_review"
      Rails.cache.write(
        pending_install_cache_key,
        {
          slug: slug,
          scan_result: result.data[:scan_result],
          pending_attributes: result.data[:pending_attributes]
        },
        expires_in: PENDING_INSTALL_TTL
      )
      redirect_to review_clawhub_index_path
    when "blocked"
      redirect_to clawhub_path(slug: slug), alert: "This skill has been blocked by the security scanner"
    end
  end

  def review
    @pending = pending_install
    unless @pending
      redirect_to clawhub_index_path, alert: "No pending install to review"
      return
    end
    @scan_result = @pending[:scan_result]
    @pending_attributes = @pending[:pending_attributes]
  end

  def confirm
    pending = pending_install
    unless pending
      redirect_to clawhub_index_path, alert: "No pending install to confirm"
      return
    end

    scan_result = pending[:scan_result].deep_symbolize_keys

    if scan_result[:status] == "blocked"
      redirect_to clawhub_index_path, alert: "Blocked skills cannot be installed"
      return
    end

    attrs = pending[:pending_attributes].deep_symbolize_keys
    skill = Skill.new(
      name: attrs[:name],
      description: attrs[:description],
      summary: attrs[:summary],
      content: attrs[:content],
      category: attrs[:category],
      source: "clawhub",
      source_url: attrs[:source_url],
      security_scan_result: scan_result.merge(
        approved_by: current_user.id,
        approved_at: Time.current.iso8601
      ),
      approved_by: current_user.id,
      approved_at: Time.current
    )

    existing = Skill.find_clawhub(source_url: attrs[:source_url], name: attrs[:name])

    if existing
      existing.update!(skill.attributes.except("id", "created_at", "updated_at"))
      clear_pending_install
      redirect_to skill_path(existing), notice: "#{existing.name} installed from ClawHub"
    elsif skill.save
      clear_pending_install
      redirect_to skill_path(skill), notice: "#{skill.name} installed from ClawHub"
    else
      redirect_to clawhub_index_path, alert: "Install failed: #{skill.errors.full_messages.join(', ')}"
    end
  end

  private

  def client
    @client ||= ClawHub::Client.new
  end

  def pending_install_cache_key
    "clawhub:pending_install:#{session.id}"
  end

  def pending_install
    Rails.cache.read(pending_install_cache_key)
  end

  def clear_pending_install
    Rails.cache.delete(pending_install_cache_key)
  end
end
