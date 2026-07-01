# frozen_string_literal: true

class CreateSkillVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :skill_versions do |t|
      t.references :skill, null: false, foreign_key: true, index: true
      t.integer    :version_number, null: false
      t.text       :content, null: false
      t.string     :checksum, null: false
      t.bigint     :changed_by_user_id
      t.bigint     :changed_by_agent_id
      t.string     :change_source, null: false, default: "manual" # manual | agent_update | import | rollback
      t.text       :change_summary
      t.bigint     :update_proposal_id  # links back to the proposal that triggered this version

      t.timestamps
    end

    add_index :skill_versions, [ :skill_id, :version_number ], unique: true
    add_index :skill_versions, :checksum
    add_index :skill_versions, :change_source
    add_index :skill_versions, :update_proposal_id
  end
end
