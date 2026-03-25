# frozen_string_literal: true

class PwaController < ApplicationController
  skip_before_action :authenticate_user!

  def manifest
    render formats: :json
  end

  def service_worker
    render layout: false, content_type: "application/javascript"
  end
end
