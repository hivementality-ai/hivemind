# frozen_string_literal: true

class ChannelThread < ApplicationRecord
  belongs_to :channel
  belongs_to :agent
  
  validates :external_thread_id, presence: true
  validates :external_thread_id, uniqueness: { scope: :channel_id }
  validates :last_active_at, presence: true
  
  before_validation :set_last_active_at, if: -> { last_active_at.blank? }
  
  scope :recent_first, -> { order(last_active_at: :desc) }
  scope :for_thread, ->(channel, thread_id) { where(channel: channel, external_thread_id: thread_id) }
  
  def touch_activity!
    update!(last_active_at: Time.current)
  end
  
  def self.claim_thread(channel:, agent:, thread_id:)
    find_or_create_by!(
      channel: channel,
      external_thread_id: thread_id
    ) do |ct|
      ct.agent = agent
      ct.last_active_at = Time.current
    end
  end
  
  def self.thread_owner(channel:, thread_id:)
    return nil unless thread_id.present?
    
    thread_record = for_thread(channel, thread_id).first
    thread_record&.agent
  end
  
  private
  
  def set_last_active_at
    self.last_active_at = Time.current
  end
end