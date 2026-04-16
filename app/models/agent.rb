# frozen_string_literal: true

class Agent < ApplicationRecord
  include RoleInstructions
  # llm_model is a native DB column — no alias needed

  DEFAULT_LOOP_CONFIG = {
    history_size: 30,
    warning_threshold: 10,
    critical_threshold: 20,
    circuit_breaker_threshold: 100,
    detectors: {
      generic_repeat: true,
      ping_pong: true,
      no_progress: true
    }
  }.freeze

  VALID_EGRESS_MODES = %w[allowlist blocklist disabled].freeze

  has_one_attached :avatar

  belongs_to :team, optional: true
  belongs_to :manager, class_name: "Agent", foreign_key: :reports_to_id, optional: true, inverse_of: :direct_reports

  has_many :direct_reports, class_name: "Agent", foreign_key: :reports_to_id, dependent: :nullify, inverse_of: :manager

  has_many :sessions, dependent: :destroy
  has_many :project_milestones, dependent: :destroy
  has_many :project_events, dependent: :destroy
  has_many :vault_entries, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :agent_budgets, dependent: :destroy
  has_many :scheduled_tasks, dependent: :destroy
  has_many :approval_requests, dependent: :destroy
  has_many :coding_agent_tasks, dependent: :destroy
  has_many :memory_entries, dependent: :destroy
  has_many :research_sessions, dependent: :destroy
  has_many :delivery_queue_entries, dependent: :destroy
  has_many :sent_team_messages, class_name: "TeamMessage", foreign_key: :from_agent_id, dependent: :destroy, inverse_of: :from_agent
  has_many :received_team_messages, class_name: "TeamMessage", foreign_key: :to_agent_id, dependent: :destroy, inverse_of: :to_agent
  has_many :parent_sub_agent_tasks, class_name: "SubAgentTask", foreign_key: :parent_agent_id, dependent: :destroy, inverse_of: :parent_agent
  has_many :child_sub_agent_tasks, class_name: "SubAgentTask", foreign_key: :child_agent_id, dependent: :destroy, inverse_of: :child_agent
  has_many :targeted_team_chat_messages, class_name: "TeamChatMessage", foreign_key: :target_agent_id, dependent: :nullify, inverse_of: :target_agent
  has_many :led_projects, class_name: "Project", foreign_key: :lead_agent_id, dependent: :nullify, inverse_of: :lead_agent
  has_many :agent_tools, dependent: :destroy
  has_many :tools, through: :agent_tools
  has_many :agent_skills, dependent: :destroy
  has_many :skills, through: :agent_skills
  has_many :tool_executions, dependent: :destroy
  has_many :agent_channels, dependent: :destroy
  has_many :channels, through: :agent_channels
  has_many :channel_threads, dependent: :destroy
  has_many :heartbeat_runs, dependent: :destroy
  has_many :agent_mcp_servers, dependent: :destroy
  has_many :mcp_servers, through: :agent_mcp_servers

  enum :status, { idle: 0, thinking: 1, executing: 2, waiting: 3, error: 4 }, default: :idle

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false }
  validates :role, presence: true
  validates :thinking_visibility, inclusion: { in: %w[hidden debug] }, allow_nil: true
  validates :thinking_budget_tokens, numericality: { greater_than: 0, less_than_or_equal_to: 128_000 }, if: :thinking_enabled?
  validate :validate_egress_policy
  validate :validate_no_self_reporting
  validate :validate_no_reporting_cycle

  attr_accessor :egress_policy_mode, :egress_policy_rules, :egress_policy_log_blocked

  before_validation :generate_slug
  before_validation :compose_egress_policy_from_virtual_attrs

  scope :active, -> { where.not(status: :error) }
  scope :by_team, ->(team) { where(team:) }
  scope :enabled, -> { where(enabled: true) }
  scope :visible, -> { where(system_agent: false) }

  # Find or create the hidden system assistant for heartbeat
  def self.system_assistant
    find_or_create_by!(name: "Assistant", system_agent: true) do |a|
      a.role = "General Assistant"
      a.enabled = true
      a.system_prompt = <<~PROMPT.strip
        You are the system heartbeat assistant. You wake up periodically to check on things.

        Your job:
        - Work through any checklist tasks you receive
        - Check your memories (memory_search) for context from previous heartbeats
        - Delegate work to the right teammate using the delegate tool — don't do everything yourself
        - Save important findings to memory so you remember them next time
        - Standing checklist items recur every heartbeat — do not remove them
        - One-off checklist items should be removed via heartbeat_write after handling
        - If something needs human attention, surface it clearly
        - Be concise and action-oriented

        If nothing needs attention, reply with exactly: HEARTBEAT_OK
      PROMPT
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
    by_slug(slug).first or raise ActiveRecord::RecordNotFound, "Couldn't find Agent with slug '#{slug}'"
  end

  def to_param
    slug
  end

  # Returns agents with the same manager (excluding self). Returns empty if no manager set.
  def peers
    return Agent.none unless reports_to_id.present?

    Agent.where(reports_to_id: reports_to_id).where.not(id: id)
  end

  # Returns the ordered chain of managers from immediate manager up to the root.
  def chain_of_command
    chain = []
    current = manager
    visited = Set.new([id])

    while current.present?
      break if visited.include?(current.id)

      chain << current
      visited.add(current.id)
      current = current.manager
    end

    chain
  end

  # Returns all agents in this agent's subtree (direct reports and their descendants).
  def org_subtree
    descendants = []
    queue = direct_reports.to_a
    visited = Set.new([id])

    while queue.any?
      node = queue.shift
      next if visited.include?(node.id)

      descendants << node
      visited.add(node.id)
      queue.concat(node.direct_reports.to_a)
    end

    descendants
  end

  def root?
    reports_to_id.nil?
  end

  def leaf?
    direct_reports.none?
  end

  private

  def generate_slug
    self.slug = name.parameterize(separator: "_") if name.present? && slug.blank?
  end

  def rebuild_team_soul
    Teams::BuildSoul.call(team: team) if team
  end

  def validate_no_self_reporting
    return unless reports_to_id.present? && id.present?

    errors.add(:reports_to_id, "cannot report to self") if reports_to_id == id
  end

  def validate_no_reporting_cycle
    return unless reports_to_id.present? && id.present?

    current = reports_to_id
    visited = Set.new([id])

    while current.present?
      if visited.include?(current)
        errors.add(:reports_to_id, "would create a reporting cycle")
        return
      end

      visited.add(current)
      current = Agent.where(id: current).pick(:reports_to_id)
    end
  end

  def compose_egress_policy_from_virtual_attrs
    return unless egress_policy_mode.present?

    mode = egress_policy_mode.to_s.strip
    return if mode.blank?

    rules = (egress_policy_rules.to_s.strip.lines.map(&:strip).reject(&:blank?)).map do |pattern|
      { "pattern" => pattern }
    end

    self.egress_policy = {
      "mode" => mode,
      "rules" => rules,
      "log_blocked" => ActiveModel::Type::Boolean.new.cast(egress_policy_log_blocked)
    }
  end

  def validate_egress_policy
    return if egress_policy.blank?

    policy = egress_policy.with_indifferent_access
    mode = policy[:mode]

    return if mode.blank?

    unless VALID_EGRESS_MODES.include?(mode)
      errors.add(:egress_policy, "has invalid mode '#{mode}'. Must be one of: #{VALID_EGRESS_MODES.join(', ')}")
      return
    end

    rules = policy[:rules]
    if rules.present?
      unless rules.is_a?(Array)
        errors.add(:egress_policy, "rules must be an array")
        return
      end

      rules.each_with_index do |rule, i|
        unless rule.is_a?(Hash) && rule["pattern"].present?
          errors.add(:egress_policy, "rule #{i + 1} must have a pattern")
        end
      end
    end
  end

  public

  def effective_tool_loop_config
    DEFAULT_LOOP_CONFIG.deep_merge(tool_loop_config || {}).with_indifferent_access
  end

  def context_window
    (model_config || {})["context_window"]&.to_i
  end

  def max_output_tokens
    (model_config || {})["max_output_tokens"]&.to_i
  end

  def inference_options
    mc = model_config || {}
    opts = {}
    opts[:temperature] = mc["temperature"].to_f if mc["temperature"].present?
    opts[:top_p] = mc["top_p"].to_f if mc["top_p"].present?
    opts[:top_k] = mc["top_k"].to_i if mc["top_k"].present?
    opts[:repeat_penalty] = mc["repeat_penalty"].to_f if mc["repeat_penalty"].present?
    opts
  end

  def effective_egress_policy
    (egress_policy.presence || {}).with_indifferent_access
  end

  def egress_enforced?
    mode = effective_egress_policy[:mode]
    mode.present? && %w[allowlist blocklist].include?(mode)
  end

  def usage_summary
    {
      total_cost: usage_records.sum(:cost_cents),
      total_tokens: usage_records.sum("input_tokens + output_tokens"),
      request_count: usage_records.count
    }
  end

  def ensure_workspace!
    path = workspace_path.presence || Rails.root.join("storage", "workspaces", id.to_s).to_s
    FileUtils.mkdir_p(path)
    update_column(:workspace_path, path) if workspace_path.blank?
    path
  end

  def usage_today
    today_start = Time.current.beginning_of_day
    usage = usage_records.where("created_at >= ?", today_start)

    {
      total_cost: usage.sum(:cost_cents),
      total_tokens: usage.sum("input_tokens + output_tokens"),
      input_tokens: usage.sum(:input_tokens),
      output_tokens: usage.sum(:output_tokens),
      request_count: usage.count
    }
  end
end
