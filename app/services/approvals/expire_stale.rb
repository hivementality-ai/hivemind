# frozen_string_literal: true

module Approvals
  # Marks pending requests past their expiry as expired and tells the chat each one came from
  # that nothing was done.
  class ExpireStale
    # @return [Integer] how many requests expired
    def self.call
      count = 0
      ApprovalRequest.pending.where("expires_at <= ?", Time.current).find_each do |approval|
        approval.with_lock do
          next unless approval.pending?

          approval.expire!
          count += 1
        end
        note_session(approval)
      end
      count
    end

    def self.note_session(approval)
      return unless approval.action == ToolCallGate::ACTION && approval.params["session_id"].present?

      ApprovalSessionNoteJob.perform_later(
        approval.params["session_id"],
        "Approval result: The request to #{CardFields.new(approval).verb} expired after 24 hours without an answer. It was not done."
      )
    end
    private_class_method :note_session
  end
end
