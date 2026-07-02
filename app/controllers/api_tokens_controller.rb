# frozen_string_literal: true

class ApiTokensController < ApplicationController
  before_action :authorize_admin_or_owner!

  def index
    @tokens = current_user.api_tokens.order(created_at: :desc)
    @new_token = ApiToken.new
  end

  def create
    token = current_user.api_tokens.build(name: token_params[:name])

    if token.save
      # raw_token is available once, immediately after save
      flash[:token] = token.raw_token
      redirect_to api_tokens_path, notice: "Token \"#{token.name}\" created. Copy it now — it won't be shown again."
    else
      @tokens = current_user.api_tokens.order(created_at: :desc)
      @new_token = token
      flash.now[:alert] = token.errors.full_messages.join(", ")
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    token = current_user.api_tokens.find(params[:id])
    token.revoke!
    redirect_to api_tokens_path, notice: "Token \"#{token.name}\" revoked."
  end

  private

  def token_params
    params.require(:api_token).permit(:name)
  end
end
