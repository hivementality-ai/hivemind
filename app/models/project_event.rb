# frozen_string_literal: true

class ProjectEvent < ApplicationRecord
  belongs_to :project
  belongs_to :project_milestone, optional: true
  belongs_to :agent, optional: true
  belongs_to :user, optional: true

  validates :event_type, presence: true
  validates :summary, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :since, ->(time) { where("created_at > ?", time) }
end
