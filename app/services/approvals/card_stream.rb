# frozen_string_literal: true

module Approvals
  # Names the Turbo stream and page container that approval cards for one chat session use.
  module CardStream
    # @param session [Session]
    # @return [String]
    def self.stream_name(session)
      "session_#{session.id}_approvals"
    end

    # @param session [Session]
    # @return [String] DOM id of the element cards are appended to
    def self.container_id(session)
      "session_#{session.id}_approval_cards"
    end
  end
end
