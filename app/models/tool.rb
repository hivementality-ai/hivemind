# frozen_string_literal: true

class Tool < ApplicationRecord
  has_many :tool_executions, dependent: :destroy
  has_many :agent_tools, dependent: :destroy
  has_many :agents, through: :agent_tools

  validates :name, presence: true, uniqueness: true
  validates :description, presence: true
  validates :executor_type, presence: true, inclusion: {
    in: %w[shell file_read file_write web_search web_fetch http_request]
  }

  scope :enabled, -> { where(enabled: true) }
  scope :builtin, -> { where(builtin: true) }

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
end
