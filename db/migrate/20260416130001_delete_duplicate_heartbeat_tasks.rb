# frozen_string_literal: true

class DeleteDuplicateHeartbeatTasks < ActiveRecord::Migration[8.0]
  # Tasks #33 and #39-49 were created by the #todo hashtag action firing on
  # heartbeat responses. They are duplicates and should be removed.
  DUPLICATE_IDS = ([33] + (39..49).to_a).freeze

  def up
    execute <<~SQL
      DELETE FROM tasks WHERE id IN (#{DUPLICATE_IDS.join(', ')})
    SQL
  end

  def down
    # No rollback — deleted task content is not stored here.
    # If needed, restore from a database backup.
  end
end
