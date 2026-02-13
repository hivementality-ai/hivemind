# frozen_string_literal: true

module Audit
  class Record
    def self.call(actor_type:, actor_id:, action:, resource: nil, metadata: {})
      new(actor_type:, actor_id:, action:, resource:, metadata:).call
    end

    def initialize(actor_type:, actor_id:, action:, resource: nil, metadata: {})
      @actor_type = actor_type
      @actor_id = actor_id.to_s
      @action = action
      @resource = resource
      @metadata = metadata
    end

    def call
      # Fire async via Sidekiq to never slow down the main request
      AuditLogJob.perform_async(
        @actor_type,
        @actor_id,
        @action,
        @resource,
        @metadata.as_json
      )

      ServiceResponse.success
    end
  end
end
