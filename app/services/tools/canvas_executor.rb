# frozen_string_literal: true

module Tools
  class CanvasExecutor < BaseExecutor
    ACTIONS = %w[render update append clear].freeze

    def call
      action = input["action"].to_s.strip
      unless ACTIONS.include?(action)
        return ServiceResponse.failure(
          error: "Unknown canvas action: #{action}. Supported: #{ACTIONS.join(', ')}"
        )
      end

      session = config[:session]
      return ServiceResponse.failure(error: "No session context available") unless session

      send(:"action_#{action}", session)
    rescue StandardError => e
      ServiceResponse.failure(error: "Canvas error: #{e.message}")
    end

    private

    def action_render(session)
      html = input["html"].to_s
      title = input["title"].to_s.strip.presence || "Canvas"
      return ServiceResponse.failure(error: "html parameter is required for render") if html.empty?

      broadcast_canvas(session, type: "render", html: html, title: title)
      canvas_url = "/sessions/#{session.id}/canvas"

      ServiceResponse.success(data: {
        output: "Canvas rendered: \"#{title}\"\nView at: #{canvas_url}"
      })
    end

    def action_update(session)
      element_id = input["element_id"].to_s.strip
      html = input["html"].to_s
      return ServiceResponse.failure(error: "element_id is required for update") if element_id.empty?
      return ServiceResponse.failure(error: "html parameter is required for update") if html.empty?

      broadcast_canvas(session, type: "update", element_id: element_id, html: html)
      ServiceResponse.success(data: { output: "Canvas element '#{element_id}' updated." })
    end

    def action_append(session)
      html = input["html"].to_s
      return ServiceResponse.failure(error: "html parameter is required for append") if html.empty?

      broadcast_canvas(session, type: "append", html: html)
      ServiceResponse.success(data: { output: "Content appended to canvas." })
    end

    def action_clear(session)
      broadcast_canvas(session, type: "clear")
      ServiceResponse.success(data: { output: "Canvas cleared." })
    end

    def broadcast_canvas(session, payload)
      ActionCable.server.broadcast("canvas_#{session.id}", payload)
    end
  end
end
