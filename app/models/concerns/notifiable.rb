# frozen_string_literal: true

module Notifiable
  extend ActiveSupport::Concern

  included do
    has_many :push_subscriptions, dependent: :destroy
  end

  def notify(title:, body:, url: "/m/", tag: nil)
    WebPush::Sender.call(
      user: self,
      title: title,
      body: body,
      url: url,
      tag: tag
    )
  end

  def notification_enabled?(category)
    prefs = try(:notification_preferences) || {}
    prefs.fetch(category.to_s, true)
  end
end
