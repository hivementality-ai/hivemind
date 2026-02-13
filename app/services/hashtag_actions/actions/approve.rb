# frozen_string_literal: true

module HashtagActions
  module Actions
    class Approve < Base
      def execute
        pending = ApprovalRequest.where(status: "pending").order(created_at: :desc)

        if payload.present? && payload.match?(/\A\d+\z/)
          request = ApprovalRequest.find_by(id: payload.to_i, status: "pending")
          return { response: "Approval request ##{payload} not found or already resolved.", status: "not_found" } unless request

          request.update!(status: "approved", resolved_at: Time.current)
          { response: "Approved request ##{request.id}: #{request.description.to_s.truncate(100)}", status: "approved" }
        elsif pending.any?
          request = pending.first
          request.update!(status: "approved", resolved_at: Time.current)
          { response: "Approved most recent request ##{request.id}: #{request.description.to_s.truncate(100)}", status: "approved" }
        else
          { response: "No pending approval requests.", status: "none" }
        end
      end
    end
  end
end
