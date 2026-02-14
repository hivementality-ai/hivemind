# frozen_string_literal: true

class Agent < ApplicationRecord
  include RoleInstructions
  # llm_model is a native DB column — no alias needed

  belongs_to :team, optional: true

  has_many :sessions, dependent: :destroy
  has_many :vault_entries, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :agent_budgets, dependent: :destroy
  has_many :scheduled_tasks, dependent: :destroy
  has_many :sent_team_messages, class_name: "TeamMessage", foreign_key: :from_agent_id, dependent: :destroy, inverse_of: :from_agent
  has_many :received_team_messages, class_name: "TeamMessage", foreign_key: :to_agent_id, dependent: :destroy, inverse_of: :to_agent
  has_many :agent_tools, dependent: :destroy
  has_many :tools, through: :agent_tools
  has_many :tool_executions, dependent: :destroy

  enum :status, { idle: 0, thinking: 1, executing: 2, waiting: 3, error: 4 }, default: :idle

  validates :name, presence: true, uniqueness: true
  validates :role, presence: true

  scope :active, -> { where.not(status: :error) }
  scope :by_team, ->(team) { where(team:) }
  scope :enabled, -> { where(enabled: true) }

  after_save :rebuild_team_soul, if: -> { team_id.present? && (saved_change_to_name? || saved_change_to_role? || saved_change_to_system_prompt? || saved_change_to_team_id?) }
  after_destroy :rebuild_team_soul, if: -> { team_id.present? }

  def current_status
    {
      status: status,
      current_task: current_task,
      updated_at: updated_at
    }
  end

  private

  def rebuild_team_soul
    Teams::BuildSoul.call(team: team) if team
  end

  public

  def usage_summary
    {
      total_cost: usage_records.sum(:cost_cents),
      total_tokens: usage_records.sum("input_tokens + output_tokens"),
      request_count: usage_records.count
    }
  end
end
