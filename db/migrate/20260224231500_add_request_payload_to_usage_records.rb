# frozen_string_literal: true

class AddRequestPayloadToUsageRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :usage_records, :request_payload, :jsonb
  end
end
