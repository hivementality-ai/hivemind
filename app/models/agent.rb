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
  has_many :agent_skills, dependent: :destroy
  has_many :skills, through: :agent_skills
  has_many :tool_executions, dependent: :destroy

  enum :status, { idle: 0, thinking: 1, executing: 2, waiting: 3, error: 4 }, default: :idle

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false }
  validates :role, presence: true
  validates :thinking_visibility, inclusion: { in: %w[hidden debug] }, allow_nil: true
  validates :thinking_budget_tokens, numericality: { greater_than: 0, less_than_or_equal_to: 128_000 }, if: :thinking_enabled?

  before_validation :generate_slug

  scope :active, -> { where.not(status: :error) }
  scope :by_team, ->(team) { where(team:) }
  scope :enabled, -> { where(enabled: true) }
  scope :visible, -> { where(system_agent: false) }

  # Find or create the hidden system assistant for heartbeat
  def self.system_assistant
    find_or_create_by!(name: "Assistant", system_agent: true) do |a|
      a.role = "General Assistant"
      a.enabled = true
      a.system_prompt = "You are the system heartbeat assistant. You read the heartbeat checklist and execute tasks. You can delegate to other agents by name using the delegate tool — use the right specialist for each job. You have persistent memory — search your memories at the start of each heartbeat for context, and save important findings so you remember them next time. Be concise and action-oriented. If there are no tasks or nothing needs attention, reply with exactly: HEARTBEAT_OK"
      a.llm_model = "claude-haiku-4-5"
    end
  end

  after_save :rebuild_team_soul, if: -> { team_id.present? && (saved_change_to_name? || saved_change_to_role? || saved_change_to_system_prompt? || saved_change_to_team_id?) }
  after_destroy :rebuild_team_soul, if: -> { team_id.present? }

  def current_status
    {
      status: status,
      current_task: current_task,
      updated_at: updated_at
    }
  end

  scope :by_slug, ->(slug) { where("LOWER(slug) = ?", slug.downcase) }

  # Find agent by slug (case-insensitive)
  def self.find_by_slug(slug)
    by_slug(slug).first
  end

  private

  def generate_slug
    self.slug = name.parameterize(separator: "_") if name.present? && slug.blank?
  end

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
