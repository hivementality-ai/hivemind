# frozen_string_literal: true

# Turns Simple mode on or off for the whole install.
class SimpleModesController < ApplicationController
  before_action :authorize_admin_or_owner!

  # PATCH /simple_mode
  def update
    SimpleMode.enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    redirect_back fallback_location: root_path,
                  notice: SimpleMode.enabled? ? "Simple mode is on." : "Simple mode is off."
  end
end
