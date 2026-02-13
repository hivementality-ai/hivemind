# frozen_string_literal: true

class TeamChatMessage < ApplicationRecord
  belongs_to :team_chat_session
  belongs_to :target_agent, class_name: "Agent", optional: true

  has_many_attached :images
  has_many_attached :documents

  validates :content, presence: true, unless: -> { images.attached? || documents.attached? }
  validates :sender_type, inclusion: { in: %w[user agent] }

  scope :chronological, -> { order(:created_at) }

  def from_user?
    sender_type == "user"
  end

  def from_agent?
    sender_type == "agent"
  end

  def sender
    from_user? ? User.find_by(id: sender_id) : Agent.find_by(id: sender_id)
  end

  # Extract @mentions from content
  # Returns { agents: [Agent, ...], broadcast: bool, god: bool }
  def self.extract_mentions(text, team)
    agents = team.agents.to_a
    mentioned = []
    broadcast = text.match?(/(?:^|\s)@team\b/i)
    god = text.match?(/(?:^|\s)@god\b/i)

    if broadcast
      mentioned = agents.select(&:enabled?)
    else
      agents.each do |agent|
        if text.match?(/(?:^|\s)@#{Regexp.escape(agent.name)}\b/i)
          mentioned << agent
        end
      end
    end

    { agents: mentioned, broadcast: broadcast, god: god }
  end
end
