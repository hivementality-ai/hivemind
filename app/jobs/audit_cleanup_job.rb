# frozen_string_literal: true

class AuditCleanupJob < ApplicationJob
  queue_as :low

  # Delete audit logs older than the retention period.
  # AuditLog is append-only (readonly? returns true for persisted records),
  # so we use delete_all to bypass the readonly check.
  RETENTION_PERIOD = 90.days

  def perform
    cutoff = RETENTION_PERIOD.ago
    deleted = AuditLog.where("created_at < ?", cutoff).delete_all
    Rails.logger.info("[AuditCleanupJob] Deleted #{deleted} audit logs older than #{cutoff.to_date}")
  end
end
