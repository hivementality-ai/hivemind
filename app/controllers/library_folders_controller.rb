# frozen_string_literal: true

# Turns watching of the library folder on or off.
class LibraryFoldersController < ApplicationController
  before_action :authorize_admin_or_owner!

  def update
    Library::FolderSetting.enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    redirect_to knowledge_documents_path, notice: "Library folder is now #{Library::FolderSetting.enabled? ? 'on' : 'off'}."
  end
end
