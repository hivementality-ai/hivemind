# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiToken, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it 'auto-generates token_digest on create' do
      token = build(:api_token)
      expect(token.token_digest).to be_present
    end

    it 'generates unique token digests' do
      token1 = create(:api_token)
      token2 = create(:api_token)
      expect(token1.token_digest).not_to eq(token2.token_digest)
    end
  end

  describe 'scopes' do
    let!(:active_token) { create(:api_token) }
    let!(:expired_token) { create(:api_token, :expired) }
    let!(:revoked_token) { create(:api_token, :revoked) }

    describe '.active' do
      it 'returns non-revoked and non-expired tokens' do
        expect(ApiToken.active).to include(active_token)
        expect(ApiToken.active).not_to include(expired_token, revoked_token)
      end
    end
  end

  describe 'token generation' do
    it 'generates raw_token on create' do
      token = build(:api_token, token_digest: nil)
      token.save!
      expect(token.raw_token).to be_present
      expect(token.raw_token).to start_with("hv_")
    end

    it 'generates unique token_digest' do
      token = build(:api_token, token_digest: nil)
      token.save!
      expect(token.token_digest).to be_present
      expect(token.token_digest.length).to eq(64) # SHA256 hex digest
    end

    it 'does not regenerate token on update' do
      token = create(:api_token)
      original_digest = token.token_digest
      token.update!(name: "New Name")
      expect(token.token_digest).to eq(original_digest)
    end
  end

  describe '.authenticate' do
    let(:user) { create(:user) }
    let!(:token) { create(:api_token, user: user, token_digest: nil) }
    let(:raw_token) { token.raw_token }

    context 'with valid token' do
      it 'returns the token' do
        result = ApiToken.authenticate(raw_token)
        expect(result).to eq(token)
      end
    end

    context 'with invalid token' do
      it 'returns nil' do
        result = ApiToken.authenticate("invalid_token")
        expect(result).to be_nil
      end
    end

    context 'with blank token' do
      it 'returns nil' do
        expect(ApiToken.authenticate(nil)).to be_nil
        expect(ApiToken.authenticate("")).to be_nil
      end
    end

    context 'with expired token' do
      let!(:expired_token) { create(:api_token, :expired, user: user, token_digest: nil) }

      it 'does not return expired token' do
        result = ApiToken.authenticate(expired_token.raw_token)
        expect(result).to be_nil
      end
    end

    context 'with revoked token' do
      let!(:revoked_token) { create(:api_token, :revoked, user: user, token_digest: nil) }

      it 'does not return revoked token' do
        result = ApiToken.authenticate(revoked_token.raw_token)
        expect(result).to be_nil
      end
    end
  end

  describe '#expired?' do
    it 'returns false when expires_at is nil' do
      token = build(:api_token, expires_at: nil)
      expect(token.expired?).to be false
    end

    it 'returns false when expires_at is in the future' do
      token = build(:api_token, expires_at: 1.day.from_now)
      expect(token.expired?).to be false
    end

    it 'returns true when expires_at is in the past' do
      token = build(:api_token, expires_at: 1.day.ago)
      expect(token.expired?).to be true
    end
  end

  describe '#revoked?' do
    it 'returns false when revoked_at is nil' do
      token = build(:api_token, revoked_at: nil)
      expect(token.revoked?).to be false
    end

    it 'returns true when revoked_at is present' do
      token = build(:api_token, revoked_at: Time.current)
      expect(token.revoked?).to be true
    end
  end

  describe '#revoke!' do
    let(:token) { create(:api_token) }

    it 'sets revoked_at to current time' do
      expect(token.revoked_at).to be_nil
      token.revoke!
      expect(token.revoked_at).to be_present
      expect(token.revoked_at).to be_within(1.second).of(Time.current)
    end

    it 'persists the revocation' do
      token.revoke!
      token.reload
      expect(token.revoked_at).to be_present
    end
  end

  describe '#touch_last_used!' do
    let(:token) { create(:api_token) }

    it 'updates last_used_at without triggering callbacks' do
      expect(token.last_used_at).to be_nil
      token.touch_last_used!
      token.reload
      expect(token.last_used_at).to be_present
      expect(token.last_used_at).to be_within(1.second).of(Time.current)
    end
  end

  describe 'factory' do
    it 'creates a valid api token' do
      expect(build(:api_token)).to be_valid
    end

    it 'creates valid tokens with traits' do
      expect(build(:api_token, :expired)).to be_valid
      expect(build(:api_token, :revoked)).to be_valid
      expect(build(:api_token, :recently_used)).to be_valid
      expect(build(:api_token, :expiring_soon)).to be_valid
    end
  end
end
