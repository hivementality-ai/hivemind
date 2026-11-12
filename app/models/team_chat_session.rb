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

  # Hold a PostgreSQL advisory lock for the whole turn, including SDK callbacks.
  # Unlike a row lock, this does not hold an open transaction during an LLM call.
  def with_execution_lock
    self.class.connection_pool.with_connection do |connection|
      locked = connection.select_value("SELECT pg_try_advisory_lock(78041, #{id.to_i})")
      return false unless locked

      begin
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(78041, #{id.to_i})")
      end
    end
    true
  end

  def responding_agents(message, responding_agent_id: nil)
    available = team.agents.enabled.order(:name)
    target_id = responding_agent_id || message.target_agent_id
    return available.where(id: target_id).to_a if target_id

    mentions = TeamChatMessage.extract_mentions(message.content.to_s, team)
    return available.to_a if mentions[:broadcast]
    return mentions[:agents].select(&:enabled?) if mentions[:agents].any?

    # A unique manager at the top of the reporting hierarchy owns synthesis.
    # Teams without a hierarchy retain their existing group-chat behavior.
    agents = available.to_a
    managers = agents.select { |candidate| candidate.reports_to_id.nil? && agents.any? { |member| member.reports_to_id == candidate.id } }
    managers.one? ? managers : agents
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
