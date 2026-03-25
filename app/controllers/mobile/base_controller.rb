# frozen_string_literal: true

module Mobile
  class BaseController < ApplicationController
    layout "mobile"

    private

    def desktop_url_for(path)
      "#{request.protocol}#{request.host_with_port}#{path}?desktop=1"
    end
    helper_method :desktop_url_for
  end
end
