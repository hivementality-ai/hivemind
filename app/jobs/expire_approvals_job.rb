# frozen_string_literal: true

# Expires approval requests nobody answered within their window.
class ExpireApprovalsJob < ApplicationJob
  queue_as :low

  def perform
    Approvals::ExpireStale.call
  end
end
