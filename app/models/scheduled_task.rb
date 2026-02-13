# frozen_string_literal: true

class ScheduledTask < ApplicationRecord
  belongs_to :agent

  validates :name, presence: true
  validates :schedule, presence: true
  validates :job_class, presence: true

  scope :enabled_tasks, -> { where(enabled: true) }
  scope :for_agent, ->(agent) { where(agent:) }

  after_initialize :set_defaults

  private

  def set_defaults
    self.params ||= {}
    self.enabled = true if enabled.nil?
  end
end
