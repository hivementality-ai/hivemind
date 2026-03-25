# frozen_string_literal: true

module MobileDetector
  extend ActiveSupport::Concern

  included do
    before_action :redirect_mobile_users
    helper_method :mobile?
  end

  private

  MOBILE_USER_AGENTS = /iPhone|iPod|Android.*Mobile|webOS|BlackBerry|Windows Phone|Opera Mini|IEMobile/i

  # Paths that have a mobile equivalent under /m/
  MOBILE_EQUIVALENT_PATHS = %w[/ /sessions /team_chats /agents /dashboard].freeze

  # Paths that should never be redirected
  SKIP_REDIRECT_PATHS = %r{\A/(api|cable|webhooks|internal|sidekiq|setup|rails)}

  def mobile?
    return @_mobile if defined?(@_mobile)

    @_mobile = if cookies[:hivemind_view_pref] == "desktop"
                 false
    elsif cookies[:hivemind_view_pref] == "mobile" || params[:mobile] == "1"
                 true
    elsif params[:desktop] == "1"
                 cookies[:hivemind_view_pref] = { value: "desktop", expires: 1.year.from_now }
                 false
    else
                 request.user_agent.to_s.match?(MOBILE_USER_AGENTS)
    end
  end

  def redirect_mobile_users
    return unless mobile?
    return if request.path.start_with?("/m/", "/m")
    return if request.path.match?(SKIP_REDIRECT_PATHS)
    return if request.xhr? || request.format.json?

    # Set mobile cookie on first detection
    if params[:mobile] == "1"
      cookies[:hivemind_view_pref] = { value: "mobile", expires: 1.year.from_now }
    end

    mobile_path = mobile_equivalent_path
    redirect_to mobile_path, allow_other_host: false if mobile_path
  end

  def mobile_equivalent_path
    path = request.path

    case path
    when "/", "/dashboard"
      "/m"
    when "/sessions"
      "/m/sessions"
    when %r{\A/sessions/(\d+)\z}
      "/m/sessions/#{$1}"
    when "/team_chats"
      "/m/team_chats"
    when %r{\A/team_chats/(\d+)\z}
      "/m/team_chats/#{$1}"
    when "/agents"
      "/m/agents"
    when %r{\A/agents/([^/]+)\z}
      "/m/agents/#{$1}"
    else
      nil # No mobile equivalent — don't redirect
    end
  end
end
