# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user, :owner) }
  let(:api_token) { create(:api_token, user: user) }

  def build_connection(headers: {}, warden_user: nil)
    env = Rack::MockRequest.env_for("/cable", headers.transform_keys { |k| "HTTP_#{k.upcase.tr('-', '_')}" })
    env["warden"] = double("warden", user: warden_user) if warden_user
    described_class.new(ActionCable.server, env)
  end

  describe "bearer token auth" do
    it "connects and identifies current_user for a valid token" do
      connection = build_connection(headers: { "Authorization" => "Bearer #{api_token.raw_token}" })

      connection.connect

      expect(connection.current_user).to eq(user)
    end

    it "touches last_used_at on the token" do
      connection = build_connection(headers: { "Authorization" => "Bearer #{api_token.raw_token}" })

      expect { connection.connect }.to change { api_token.reload.last_used_at }.from(nil)
    end

    it "rejects the connection for an invalid token" do
      connection = build_connection(headers: { "Authorization" => "Bearer hv_not_a_real_token" })

      expect { connection.connect }.to raise_error(ActionCable::Connection::Authorization::UnauthorizedError)
    end

    it "rejects the connection for a revoked token" do
      revoked_token = create(:api_token, :revoked, user: user)
      connection = build_connection(headers: { "Authorization" => "Bearer #{revoked_token.raw_token}" })

      expect { connection.connect }.to raise_error(ActionCable::Connection::Authorization::UnauthorizedError)
    end

    it "rejects the connection when no Authorization header and no warden session are present" do
      connection = build_connection

      expect { connection.connect }.to raise_error(ActionCable::Connection::Authorization::UnauthorizedError)
    end
  end

  describe "warden/Devise-cookie auth (web UI)" do
    it "still connects and identifies current_user via warden when there is no bearer token" do
      connection = build_connection(warden_user: user)

      connection.connect

      expect(connection.current_user).to eq(user)
    end

    it "prefers the warden session over a bearer token when both are present" do
      other_user = create(:user, :owner)
      connection = build_connection(
        headers: { "Authorization" => "Bearer #{api_token.raw_token}" },
        warden_user: other_user
      )

      connection.connect

      expect(connection.current_user).to eq(other_user)
    end
  end
end
