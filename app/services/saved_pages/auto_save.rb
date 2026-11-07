# frozen_string_literal: true

module SavedPages
  # Keeps long research reports and scheduled-run answers as pages without being asked.
  class AutoSave
    class << self
      # Saves a long finished research report once; short ones are left in the chat.
      # @param research_session [ResearchSession]
      # @param report [String]
      # @return [SavedPage, nil]
      def research(research_session, report)
        return unless long_enough?(report)

        SavedPage.find_by(research_session: research_session) || SavedPage.create!(
          title: research_session.query.to_s.truncate(SavedPage::TITLE_LIMIT),
          body: report,
          agent: research_session.agent,
          session: research_session.session,
          research_session: research_session,
          source_kind: "research"
        )
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.warn("[SavedPages] research auto-save failed: #{e.message}")
        nil
      end

      # Saves a long answer from a scheduled run and links the page at its end.
      # @param session [Session]
      # @param content [String] the final answer
      # @return [String] the answer, with a link to the page when one was saved
      def scheduled(session, content)
        return content unless session.metadata&.dig("type") == "scheduled" && long_enough?(content)

        page = SavedPage.create!(
          title: scheduled_title(session, content),
          body: content,
          agent: session.agent,
          session: session,
          source_kind: "scheduled"
        )
        "#{content}\n\n[Open the saved page](#{Rails.application.routes.url_helpers.saved_page_path(page)})"
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.warn("[SavedPages] scheduled auto-save failed: #{e.message}")
        content
      end

      private

      def long_enough?(text)
        text.to_s.length >= SavedPage::AUTO_SAVE_MIN_CHARS
      end

      def scheduled_title(session, content)
        name = session.title.to_s.delete_prefix("Scheduled: ").presence || SavedPage.title_from(content)
        "#{name} (#{Time.current.strftime('%b %-d')})".truncate(SavedPage::TITLE_LIMIT)
      end
    end
  end
end
