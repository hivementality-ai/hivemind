# frozen_string_literal: true

class ScheduledTask < ApplicationRecord
  belongs_to :agent

  validates :name, presence: true
  validates :schedule, presence: true
  validates :job_class, presence: true, on: :create

  before_validation :set_default_job_class
  validates :confirmation_status, inclusion: { in: %w[pending active disabled paused] }, allow_nil: true

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :active, -> { where(confirmation_status: "active") }
  scope :pending_confirmation, -> { where(confirmation_status: "pending") }

  before_validation :set_default_confirmation_status

  def enabled?
    enabled
  end

  def disabled?
    !enabled
  end

  def last_run_status
    if last_error_at.present? && (last_run_at.nil? || last_error_at > last_run_at)
      "error"
    elsif last_run_at.present?
      "success"
    else
      "never_run"
    end
  end

  def human_readable_schedule
    CronParser.parse(schedule)
  end

  private

  def set_default_confirmation_status
    self.confirmation_status ||= "active"
  end

  def set_default_job_class
    self.job_class ||= "ScheduledAgentJob"
  end
end
