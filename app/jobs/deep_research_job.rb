# frozen_string_literal: true

class DeepResearchJob < ApplicationJob
  queue_as :research

  def perform(research_session_id)
    @rs = ResearchSession.find(research_session_id)
    @rs.update!(status: "running", started_at: Time.current)

    Research::Loop.new(research_session: @rs).call
  rescue Research::CancelledError
    @rs.update!(status: "cancelled", completed_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("[DeepResearch] Task #{@rs&.task_key} failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    @rs&.fail!(e.message)
    inject_error_result(e.message)
  end

  private

  def inject_error_result(error_message)
    return unless @rs&.session

    callback_message = <<~MSG.strip
      [Deep Research Failed] #{@rs.query.truncate(100)}

      Error: #{error_message.truncate(500)}

      (Task ID: #{@rs.task_key})
    MSG

    ChatStreamJob.perform_later(
      @rs.session.id,
      callback_message,
      []
    )
  end
end
