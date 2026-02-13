# frozen_string_literal: true

class AuditLog < ApplicationRecord
  validates :actor_type, presence: true
  validates :actor_id, presence: true
  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_actor, ->(type, id) { where(actor_type: type, actor_id: id) }
  scope :by_action, ->(action) { where(action:) }

  # Append-only: prevent updates and deletes
  def readonly?
    persisted?
  end

  def self.record(actor_type:, actor_id:, action:, resource: nil, metadata: {})
    create!(
      actor_type:,
      actor_id: actor_id.to_s,
      action:,
      resource:,
      metadata:
    )
  end
end
