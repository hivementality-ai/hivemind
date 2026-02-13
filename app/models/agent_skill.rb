# frozen_string_literal: true

class AgentSkill < ApplicationRecord
  belongs_to :agent
  belongs_to :skill
end
