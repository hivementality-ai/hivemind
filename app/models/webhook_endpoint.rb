# frozen_string_literal: true

# An outbound webhook subscription. POSTs signed event payloads to an external
# URL when subscribed lifecycle events fire. Counterpart to the inbound
# WebhooksController — same HMAC-SHA256 hexdigest scheme (see Channels::BaseAdapter).
class WebhookEndpoint < ApplicationRecord
  # Consecutive delivery failures before the endpoint auto-disables.
  MAX_FAILURES = 5

  belongs_to :agent, optional: true # nil agent + nil team = global scope
  belongs_to :team, optional: true

  encrypts :secret # signing key — never logged, stored like other secrets

  before_validation :ensure_secret, on: :create

  validates :url, presence: true
  validate :url_must_be_https
  validate :event_types_must_be_array

  scope :enabled, -> { where(enabled: true) }
  # jsonb containment: endpoints whose event_types array includes the event.
  scope :subscribed_to, ->(event) { where("event_types @> ?", [ event ].to_json) }

  # Endpoints visible to a given agent/team plus global ones.
  # Single OR'd clause so it AND-composes with chained scopes (.enabled etc).
  def self.in_scope(agent: nil, team: nil)
    clauses = [ "(agent_id IS NULL AND team_id IS NULL)" ]
    params = []
    if agent
      clauses << "agent_id = ?"
      params << agent.id
    end
    if team
      clauses << "team_id = ?"
      params << team.id
    end
    where(clauses.join(" OR "), *params)
  end

  def subscribed_to?(event)
    event_types.to_a.include?(event)
  end

  # Reset failure tracking on a successful delivery.
  def record_success!(status)
    update!(last_delivered_at: Time.current, last_status: status, failure_count: 0)
  end

  # Increment consecutive failures; disable once the ceiling is hit.
  def record_failure!(status = nil)
    next_count = failure_count + 1
    update!(failure_count: next_count, last_status: status, enabled: next_count < MAX_FAILURES)
  end

  private

  def ensure_secret
    self.secret = SecureRandom.hex(32) if secret.blank?
  end

  def url_must_be_https
    return if url.blank?

    uri = URI.parse(url)
    # ponytail: https-only is the SSRF floor. Add private-IP/DNS-rebind blocking
    # (resolve host, reject RFC1918/link-local) if endpoints become user-supplied at scale.
    errors.add(:url, "must be a valid HTTPS URL") unless uri.is_a?(URI::HTTPS) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid URL")
  end

  def event_types_must_be_array
    return if event_types.is_a?(Array) && event_types.all?(String)

    errors.add(:event_types, "must be an array of event name strings")
  end
end
