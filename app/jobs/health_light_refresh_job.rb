# frozen_string_literal: true

# Refreshes the cached header health light. Queued by Platform::HealthLight
# when its snapshot goes stale, so page loads never wait on a check.
class HealthLightRefreshJob < ApplicationJob
  queue_as :low

  def perform
    Platform::HealthLight.refresh!
  end
end
