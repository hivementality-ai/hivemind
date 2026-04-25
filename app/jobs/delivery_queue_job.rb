# frozen_string_literal: true

class DeliveryQueueJob < ApplicationJob
  queue_as :system

  def perform
    result = Channels::DeliveryQueue.process_pending
    if result.success?
      Rails.logger.info("[DeliveryQueueJob] Processed: #{result.data[:sent]} sent, #{result.data[:failed]} failed")
    else
      Rails.logger.error("[DeliveryQueueJob] Error: #{result.error}")
    end
  end
end
