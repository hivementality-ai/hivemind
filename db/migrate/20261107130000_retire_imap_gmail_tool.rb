# frozen_string_literal: true

class RetireImapGmailTool < ActiveRecord::Migration[8.1]
  def up
    Tools::GmailRetirement.call
  end

  def down
    # The retired tool stays disabled; nothing to restore.
  end
end
