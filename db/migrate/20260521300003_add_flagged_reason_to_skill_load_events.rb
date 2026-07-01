# frozen_string_literal: true

class AddFlaggedReasonToSkillLoadEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :skill_load_events, :flagged_reason, :text
    add_column :skill_load_events, :flagged_at, :datetime
  end
end
