# frozen_string_literal: true

class SkillTool < ApplicationRecord
  belongs_to :skill
  belongs_to :tool
end
