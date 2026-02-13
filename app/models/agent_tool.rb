# frozen_string_literal: true

class AgentTool < ApplicationRecord
  belongs_to :agent
  belongs_to :tool
end
