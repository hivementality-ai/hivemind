# frozen_string_literal: true

class ApiController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_token

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: "Not found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def authenticate_api_token
    token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

    return render json: { error: "Unauthorized" }, status: :unauthorized unless token

    @current_api_token = ApiToken.authenticate(token)

    return render json: { error: "Unauthorized" }, status: :unauthorized unless @current_api_token

    @current_api_token.touch_last_used!
  end

  def current_api_token
    @current_api_token
  end
end
