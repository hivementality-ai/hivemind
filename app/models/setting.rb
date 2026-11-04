# frozen_string_literal: true

class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  after_commit :reconcile_subsystem_schedule, if: -> { Platform::SubsystemSchedule::WATCHED_SETTING_KEYS.include?(key) }

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.update!(value: value)
  end

  private

  def reconcile_subsystem_schedule
    Platform::SubsystemSchedule.reconcile!
  end
end
