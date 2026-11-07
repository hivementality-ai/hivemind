# frozen_string_literal: true

# Saved pages: anyone signed in can read; saving and renaming need more than view-only access.
class SavedPagesController < ApplicationController
  LIST_LIMIT = 200

  before_action :require_editor!, only: [ :create, :update, :destroy ]
  before_action :set_page, only: [ :show, :update, :destroy ]
  before_action :authorize_delete!, only: [ :destroy ]

  def index
    @query = params[:q].to_s.strip
    @pages = SavedPage.search_title(@query).includes(:agent).newest_first.limit(LIST_LIMIT)
  end

  def show; end

  # Keeps one assistant reply from a chat as a page.
  def create
    session = Session.find(params[:session_id])
    message = Array(session.transcript)[params[:message_index].to_i] if params[:message_index].to_s.match?(/\A\d+\z/)

    if message.blank? || message["role"] != "assistant" || message["content"].to_s.strip.empty?
      return redirect_to(session_path(session), alert: "That message can't be saved as a page.")
    end

    page = SavedPage.create!(
      title: SavedPage.title_from(message["content"]),
      body: message["content"],
      agent: session.agent,
      session: session,
      created_by: current_user,
      source_kind: SavedPage.kind_for(session)
    )
    redirect_to saved_page_path(page), notice: "Saved as a page."
  end

  # Only the title can change.
  def update
    if @page.update(title: params.dig(:saved_page, :title).to_s.strip)
      redirect_to saved_page_path(@page), notice: "Title changed."
    else
      redirect_to saved_page_path(@page), alert: "A page needs a title."
    end
  end

  def destroy
    @page.destroy!
    redirect_to saved_pages_path, notice: "Page deleted."
  end

  private

  def set_page
    @page = SavedPage.find(params[:id])
  end

  def require_editor!
    return unless current_user.viewer?

    redirect_back fallback_location: saved_pages_path, alert: "Your account can read pages but not change them."
  end

  def authorize_delete!
    return if current_user.admin? || current_user.owner? || @page.created_by_id == current_user.id

    redirect_to saved_page_path(@page), alert: "Only the person who saved a page, or an admin, can delete it."
  end
end
