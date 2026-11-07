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

  validates :quiet_start_hour, :quiet_end_hour, :digest_hour,
            numericality: { only_integer: true, in: 0..23 }, allow_nil: true
  validate :quiet_window_complete

  # @param time [Time]
  # @return [Boolean] whether the time falls inside the quiet window (which may wrap past midnight)
  def quiet_now?(time = Time.current)
    return false if quiet_start_hour.nil? || quiet_end_hour.nil?

    hour = time.in_time_zone.hour
    if quiet_start_hour < quiet_end_hour
      hour >= quiet_start_hour && hour < quiet_end_hour
    else
      hour >= quiet_start_hour || hour < quiet_end_hour
    end
  end

  # A digest is due on the first check after the digest hour passes since the oldest held item
  # (or since the previous check when nothing is held).
  # @return [Boolean]
  def digest_due?(time = Time.current)
    return false if digest_hour.nil?

    since = held_changes["since"].presence || last_checked_at&.iso8601
    since.present? && digest_day(time) > digest_day(Time.zone.parse(since))
  end

  # @return [Boolean] whether held changes must keep waiting at this time
  def hold_closed?(time = Time.current)
    quiet_now?(time) || (digest_hour.present? && !digest_due?(time))
  end

  # @return [Array<Hash>] the items being held, string-keyed
  def held_items
    Array(held_changes["items"])
  end

  def holding?
    held_items.any? || held_changes["page_changed"] == true
  end

  # @return [Integer] items held, including those past the cap
  def held_count
    held_items.size + held_changes["extra"].to_i
  end

  # @return [Integer, nil] the hour held changes go out
  def release_hour
    digest_hour || quiet_end_hour
  end

  # Merges new items into what is already held, by id, keeping at most Precheck::MAX_ITEMS.
  # @param items [Array<Hash>] items with :id, :title, :link
  # @param extra [Integer] new items the check already dropped past the cap
  # @param page_changed [Boolean] a watched page changed (pages carry no items)
  def hold(items, extra: 0, page_changed: false)
    merged = (held_items + items.map { |item| item.to_h.stringify_keys }).uniq { |item| item["id"] }
    kept = merged.first(ScheduledTasks::Precheck::MAX_ITEMS)
    self.held_changes = {
      "items" => kept,
      "extra" => held_changes["extra"].to_i + extra.to_i + (merged.size - kept.size),
      "page_changed" => page_changed || held_changes["page_changed"] == true,
      "since" => held_changes["since"].presence || Time.current.iso8601
    }
  end

  # Empties the hold and returns what it contained.
  # @return [Hash] with "items", "extra" and "page_changed"
  def release_held
    released = { "items" => held_items, "extra" => held_changes["extra"].to_i, "page_changed" => held_changes["page_changed"] == true }
    self.held_changes = {}
    released
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

  def digest_day(time)
    (time.in_time_zone - digest_hour.hours).to_date
  end

  def quiet_window_complete
    return if quiet_start_hour.nil? && quiet_end_hour.nil?

    if quiet_start_hour.nil? || quiet_end_hour.nil?
      errors.add(:base, "Quiet hours need both a start and an end")
    elsif quiet_start_hour == quiet_end_hour
      errors.add(:base, "Quiet hours can't start and end at the same time")
    end
  end

  def set_default_confirmation_status
    self.confirmation_status ||= "active"
  end

  def set_default_job_class
    self.job_class ||= "ScheduledAgentJob"
  end
end
