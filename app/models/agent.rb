# frozen_string_literal: true

class Agent < ApplicationRecord
  belongs_to :team, optional: true

  has_many :sessions, dependent: :destroy
  has_many :vault_entries, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :agent_budgets, dependent: :destroy
  has_many :scheduled_tasks, dependent: :destroy
  has_many :sent_team_messages, class_name: "TeamMessage", foreign_key: :from_agent_id, dependent: :destroy, inverse_of: :from_agent
  has_many :received_team_messages, class_name: "TeamMessage", foreign_key: :to_agent_id, dependent: :destroy, inverse_of: :to_agent

  enum :status, { idle: 0, thinking: 1, executing: 2, waiting: 3, error: 4 }, default: :idle

  validates :name, presence: true, uniqueness: true
  validates :role, presence: true

  scope :active, -> { where.not(status: :error) }
  scope :by_team, ->(team) { where(team:) }
end
