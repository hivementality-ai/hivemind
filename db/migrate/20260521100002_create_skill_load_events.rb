# frozen_string_literal: true

class CreateSkillLoadEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :skill_load_events do |t|
      t.references :skill, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.references :session, null: true, foreign_key: true
      t.string :load_tier, null: false             # "core", "contextual", "manual"
      t.float :relevance_score, null: true          # score at time of contextual load
      t.string :trigger_context, null: true, limit: 500  # snippet of context that triggered load
      t.boolean :was_helpful, null: true            # set later by feedback
      t.datetime :created_at, null: false
    end

    add_index :skill_load_events, :load_tier
    add_index :skill_load_events, :created_at
    add_index :skill_load_events, [ :agent_id, :skill_id ], name: "index_skill_load_events_on_agent_and_skill"
  end
end
