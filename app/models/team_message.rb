# frozen_string_literal: true

class TeamMessage < ApplicationRecord
  belongs_to :from_agent, class_name: "Agent", inverse_of: :sent_team_messages
  belongs_to :to_agent, class_name: "Agent", optional: true, inverse_of: :received_team_messages
  belongs_to :team

  validates :content, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_team, ->(team) { where(team:) }
  scope :broadcast_messages, -> { where(to_agent_id: nil) }

  after_initialize :set_defaults

  private

  def set_defaults
    self.metadata ||= {}
    self.message_type ||= "chat"
  end
end
