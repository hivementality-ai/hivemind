# frozen_string_literal: true

module AuditLogsHelper
  ACTOR_BADGE_CLASSES = {
    "agent"  => "bg-blue-500/20 text-blue-300",
    "user"   => "bg-green-500/20 text-green-300",
    "system" => "bg-amber-500/20 text-amber-300"
  }.freeze

  def actor_badge_class(actor_type)
    ACTOR_BADGE_CLASSES.fetch(actor_type.to_s, "bg-surface-raised text-text-muted")
  end
end
