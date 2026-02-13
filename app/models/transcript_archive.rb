# frozen_string_literal: true

class TranscriptArchive < ApplicationRecord
  belongs_to :session

  validates :transcript, presence: true

  after_initialize :set_defaults

  private

  def set_defaults
    self.archived_at ||= Time.current
  end
end
