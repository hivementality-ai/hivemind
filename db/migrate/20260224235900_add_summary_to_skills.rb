# frozen_string_literal: true

class AddSummaryToSkills < ActiveRecord::Migration[8.0]
  def up
    add_column :skills, :summary, :string

    # Auto-populate summary from first meaningful line of content
    Skill.find_each do |skill|
      first_line = skill.content.to_s.lines
                        .map(&:strip)
                        .reject { |l| l.blank? || l.start_with?("#") }
                        .first
      summary = first_line&.truncate(150) || skill.name.titleize
      skill.update_column(:summary, summary)
    end
  end

  def down
    remove_column :skills, :summary
  end
end
