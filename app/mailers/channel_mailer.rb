# frozen_string_literal: true

# Sends agent replies out over the email channel. Uses the app's configured
# ActionMailer/SMTP delivery.
class ChannelMailer < ApplicationMailer
  def agent_reply(to:, from:, subject:, body:)
    mail(to: to, from: from, subject: subject) do |format|
      format.text { render plain: body }
    end
  end
end
