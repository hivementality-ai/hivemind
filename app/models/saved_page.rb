# frozen_string_literal: true

# A long piece of agent work kept as a page with its own address.
class SavedPage < ApplicationRecord
  SOURCE_KINDS = %w[chat research scheduled].freeze
  KIND_LABELS = { "chat" => "From a chat", "research" => "Research result", "scheduled" => "Scheduled task" }.freeze
  TITLE_LIMIT = 120
  AUTO_SAVE_MIN_CHARS = 1500

  belongs_to :agent
  belongs_to :session, optional: true
  belongs_to :research_session, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :title, presence: true, length: { maximum: TITLE_LIMIT }
  validates :body, presence: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # @param query [String, nil] words from a title; blank returns everything
  # @return [ActiveRecord::Relation] pages whose title contains the text, ignoring case
  def self.search_title(query)
    return all if query.blank?

    where("title ILIKE ?", "%#{sanitize_sql_like(query.to_s.strip)}%")
  end

  # @param body [String] markdown text
  # @return [String] the first heading, else the first line without markdown marks, shortened to fit
  def self.title_from(body)
    lines = body.to_s.lines.map(&:strip).reject(&:empty?)
    heading = lines.find { |line| line.start_with?("#") }
    text = (heading || lines.first).to_s.gsub(/\A#+\s*|[*_`>]/, "").strip
    text.empty? ? "Untitled page" : text.truncate(TITLE_LIMIT)
  end

  # @return [String] plain-words description of where the page came from
  def kind_label
    KIND_LABELS.fetch(source_kind)
  end

  # @param session [Session, nil]
  # @return [String] "scheduled" for a scheduled run, otherwise "chat"
  def self.kind_for(session)
    session&.metadata&.dig("type") == "scheduled" ? "scheduled" : "chat"
  end
end
