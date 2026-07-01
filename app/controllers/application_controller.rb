# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include MobileDetector

  before_action :authenticate_user!

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # Restricts access to admin and owner roles. Used as a before_action for
  # sensitive operations that should not be accessible to viewers or operators.
  def authorize_admin_or_owner!
    return if current_user.admin? || current_user.owner?

    redirect_to root_path, alert: "Access denied."
  end
end
