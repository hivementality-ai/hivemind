# frozen_string_literal: true

# Fans an event out to every enabled WebhookEndpoint subscribed to it, within
# scope (the given agent/team plus global endpoints). One delivery job per match.
#
#   WebhookEmitter.emit("task.completed", { task_id: 1 }, agent: agent)
class WebhookEmitter
  def self.emit(event_type, data, agent: nil, team: nil)
    WebhookEndpoint
      .enabled
      .subscribed_to(event_type)
      .in_scope(agent: agent, team: team)
      .find_each do |endpoint|
        WebhookDeliveryJob.perform_later(endpoint.id, event_type, data)
      end
  end
end
