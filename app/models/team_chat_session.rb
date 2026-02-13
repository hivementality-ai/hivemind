# frozen_string_literal: true

class TeamChatSession < ApplicationRecord
  belongs_to :team
  belongs_to :user

  has_many :team_chat_messages, dependent: :destroy
  has_many :agent_sessions, class_name: "Session", dependent: :nullify

  enum :status, { active: 0, archived: 1 }, default: :active

  validates :session_key, presence: true, uniqueness: true

  before_validation :generate_session_key, on: :create

  scope :recent, -> { order(updated_at: :desc) }

  def recent_messages(limit: 50)
    team_chat_messages.order(:created_at).last(limit)
  end

  # Get or create a persistent Session for an agent within this team chat
  def session_for(agent)
    existing = agent_sessions.find_by(agent: agent)
    return existing if existing

    Session.create!(
      agent: agent,
      team_chat_session: self,
      session_key: "tc-#{session_key}-#{agent.id}",
      status: :active,
      transcript: [],
      metadata: { team_chat_session_id: id, team_id: team_id },
      last_activity_at: Time.current
    )
  end

  private

  def generate_session_key
    self.session_key ||= SecureRandom.uuid
  end
end
