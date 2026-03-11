# frozen_string_literal: true

module Channels
  class DeliveryQueue
    BACKOFF_BASE = 30

    def self.enqueue(channel:, recipient:, content:, agent: nil, session: nil, options: {})
      entry = DeliveryQueueEntry.create!(
        channel: channel,
        recipient: recipient,
        content: content,
        agent: agent,
        session: session,
        options: options,
        status: "pending",
        next_attempt_at: Time.current
      )

      ServiceResponse.success(data: { entry: entry })
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to enqueue: #{e.message}")
    end

    def self.process_pending
      entries = DeliveryQueueEntry.due_for_retry.order(:next_attempt_at).limit(50)
      results = entries.map { |entry| deliver(entry) }

      sent = results.count(&:success?)
      failed = results.count { |r| !r.success? }

      ServiceResponse.success(data: { sent: sent, failed: failed })
    end

    def self.deliver(entry)
      adapter = Channels::Registry.adapter_for(entry.channel)

      result = adapter.send_message(
        to: entry.recipient,
        content: entry.content
      )

      if result.success?
        entry.update!(status: "sent", sent_at: Time.current, attempts: entry.attempts + 1)
        ServiceResponse.success(data: { entry: entry })
      else
        handle_failure(entry, result.error)
      end
    rescue StandardError => e
      handle_failure(entry, e.message)
    end

    def self.handle_failure(entry, error_message)
      new_attempts = entry.attempts + 1

      if new_attempts >= entry.max_attempts
        entry.update!(
          status: "dead_letter",
          attempts: new_attempts,
          last_error: error_message
        )
        Rails.logger.error("[DeliveryQueue] Dead letter: #{entry.id} — #{error_message}")
      else
        delay = BACKOFF_BASE * (2**new_attempts)
        entry.update!(
          status: "pending",
          attempts: new_attempts,
          next_attempt_at: Time.current + delay.seconds,
          last_error: error_message
        )
      end

      ServiceResponse.failure(error: error_message)
    end

    private_class_method :handle_failure
  end
end
