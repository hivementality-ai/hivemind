# frozen_string_literal: true

module Api
  module V1
    class HashtagActionsController < ApplicationController
      skip_before_action :authenticate_user!, only: [:index]
      skip_before_action :verify_authenticity_token, only: [:index]

      # GET /api/v1/hashtag_actions
      # Returns list of valid hashtag actions with descriptions
      def index
        actions = [
          { name: "remember", description: "Save something to memory" },
          { name: "forget", description: "Remove a memory" },
          { name: "search", description: "Search memories" },
          { name: "todo", description: "Create a task" },
          { name: "schedule", description: "Schedule a task" },
          { name: "summarize", description: "Summarize conversation" },
          { name: "status", description: "Show agent status" },
          { name: "reset", description: "Reset conversation" },
          { name: "help", description: "Show available actions" },
          { name: "mood", description: "Set conversation mood" },
          { name: "voice", description: "Toggle voice mode" },
          { name: "image", description: "Generate an image" },
          { name: "handoff", description: "Hand off to another agent" },
          { name: "delegate", description: "Delegate to a specialist" },
          { name: "private", description: "Mark as private" },
          { name: "approve", description: "Approve a pending action" },
          { name: "deny", description: "Deny a pending action" }
        ]

        render json: actions
      end
    end
  end
end
