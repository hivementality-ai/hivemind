# frozen_string_literal: true

# Recurring scan of the watched library folder (see Library::FolderScan).
class LibraryFolderScanJob < ApplicationJob
  queue_as :system

  def perform
    root = Library::FolderSetting.root
    return unless Library::FolderSetting.enabled?(root: root)

    Library::FolderScan.new(root: root).call
  end
end
