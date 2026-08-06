# frozen_string_literal: true

# Per-user stream for desktop/mobile push-style notifications delivered over
# ActionCable (alongside the existing web push delivery in
# WebPush::NotificationTriggers). A user can only ever subscribe to their own
# stream — authorization is the connection's verified current_user, nothing
# client-supplied.
class NotificationChannel < ApplicationCable::Channel
  def subscribed
    if current_user
      stream_from "notifications_user_#{current_user.id}"
    else
      reject
    end
  end

  def unsubscribed
    # Cleanup
  end
end
