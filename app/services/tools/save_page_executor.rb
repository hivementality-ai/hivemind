# frozen_string_literal: true

module Tools
  # Lets an agent keep its own long output as a saved page with its own address.
  class SavePageExecutor < BaseExecutor
    def call
      return ServiceResponse.failure(error: "Agent context required") unless agent

      body = input["body"].to_s.strip
      return ServiceResponse.failure(error: "Nothing to save: body is empty") if body.empty?

      session = config[:session]
      page = SavedPage.create!(
        title: input["title"].to_s.strip.presence&.truncate(SavedPage::TITLE_LIMIT) || SavedPage.title_from(body),
        body: body,
        agent: agent,
        session: session,
        source_kind: SavedPage.kind_for(session)
      )

      ServiceResponse.success(data: {
        output: "Saved as a page: #{page.title}\nLink for the person: [#{page.title}](#{Rails.application.routes.url_helpers.saved_page_path(page)})",
        exit_code: 0,
        page_id: page.id
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Could not save the page: #{e.message}")
    end
  end
end
