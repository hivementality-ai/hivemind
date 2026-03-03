# frozen_string_literal: true

class Tool < ApplicationRecord
  has_many :tool_executions, dependent: :destroy
  has_many :agent_tools, dependent: :destroy
  has_many :agents, through: :agent_tools
  has_many :skill_tools, dependent: :destroy
  has_many :skills, through: :skill_tools

  validates :name, presence: true, uniqueness: true
  validates :description, presence: true
  validates :executor_type, presence: true, inclusion: {
    in: %w[shell file_read file_write file_send file_edit web_search web_fetch http_request browser memory_search image image_generate cron cron_script message heartbeat_write delegate spawn spawn_status sessions_list sessions_send sessions_history session_status agents_list gateway tts gmail drive cloud_storage pdf_read jira trello email custom_script coding_agent coding_agent_status deep_research deep_research_status vault voice_call places_search ask_user plan_mode glob grep]
  }
  validates :script_template, presence: true, if: -> { executor_type == "custom_script" }

  scope :enabled, -> { where(enabled: true) }
  scope :builtin, -> { where(builtin: true) }
  scope :custom, -> { where(builtin: false) }

  # Convert to LLM tool format (works for both Anthropic and OpenAI)
  def to_llm_tool
    {
      name: name,
      description: description,
      input_schema: {
        type: "object",
        properties: parameters_schema["properties"] || {},
        required: parameters_schema["required"] || []
      }
    }
  end

  # Check if all required credentials are configured in the vault
  def credentials_ready?
    Tools::CredentialChecker.ready?(self)
  end

  # Get human-readable summary of missing credentials
  def missing_credentials_summary
    Tools::CredentialChecker.missing_summary(self)
  end

  # For custom_script tools, merge script_template into config for the executor
  def effective_config
    if executor_type == "custom_script" && script_template.present?
      (config || {}).merge("script_template" => script_template)
    else
      config || {}
    end
  end
end
