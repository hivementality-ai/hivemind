# frozen_string_literal: true

class AuditLogJob
  include Sidekiq::Job

  sidekiq_options queue: "low", retry: 3

  def perform(actor_type, actor_id, action, resource, metadata)
    AuditLog.record(
      actor_type:,
      actor_id:,
      action:,
      resource:,
      metadata: metadata || {}
    )
  end
end
