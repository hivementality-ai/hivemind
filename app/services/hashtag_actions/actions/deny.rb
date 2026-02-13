# frozen_string_literal: true

module HashtagActions
  module Actions
    class Deny < Base
      def execute
        pending = ApprovalRequest.where(status: "pending").order(created_at: :desc)

        if payload.present? && payload.match?(/\A\d+\z/)
          request = ApprovalRequest.find_by(id: payload.to_i, status: "pending")
          return { response: "Approval request ##{payload} not found or already resolved.", status: "not_found" } unless request

          request.update!(status: "denied", resolved_at: Time.current)
          { response: "Denied request ##{request.id}: #{request.description.to_s.truncate(100)}", status: "denied" }
        elsif pending.any?
          request = pending.first
          request.update!(status: "denied", resolved_at: Time.current)
          { response: "Denied most recent request ##{request.id}: #{request.description.to_s.truncate(100)}", status: "denied" }
        else
          { response: "No pending approval requests.", status: "none" }
        end
      end
    end
  end
end
