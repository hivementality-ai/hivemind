# frozen_string_literal: true

class ToolExecution < ApplicationRecord
  belongs_to :tool
  belongs_to :agent
  belongs_to :session

  validates :status, presence: true, inclusion: {
    in: %w[pending approved running completed failed denied]
  }

  scope :recent, -> { order(created_at: :desc) }
end
