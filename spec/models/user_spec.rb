# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_many(:api_tokens).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:role) }
    it { should validate_presence_of(:email) }
  end

  describe 'enums' do
    it { should define_enum_for(:role).with_values(viewer: 0, operator: 1, admin: 2, owner: 3).with_default(:owner) }
  end

  describe 'devise modules' do
    it 'includes database_authenticatable' do
      expect(User.devise_modules).to include(:database_authenticatable)
    end

    it 'includes registerable' do
      expect(User.devise_modules).to include(:registerable)
    end

    it 'includes recoverable' do
      expect(User.devise_modules).to include(:recoverable)
    end

    it 'includes rememberable' do
      expect(User.devise_modules).to include(:rememberable)
    end

    it 'includes validatable' do
      expect(User.devise_modules).to include(:validatable)
    end
  end

  describe 'password complexity' do
    it 'rejects passwords without uppercase letters' do
      user = build(:user, password: 'password1!', password_confirmation: 'password1!')
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include('must include at least one uppercase letter')
    end

    it 'rejects passwords without lowercase letters' do
      user = build(:user, password: 'PASSWORD1!', password_confirmation: 'PASSWORD1!')
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include('must include at least one lowercase letter')
    end

    it 'rejects passwords without digits' do
      user = build(:user, password: 'Password!', password_confirmation: 'Password!')
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include('must include at least one digit')
    end

    it 'rejects passwords without special characters' do
      user = build(:user, password: 'Password1', password_confirmation: 'Password1')
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include('must include at least one special character')
    end

    it 'rejects passwords shorter than 8 characters' do
      user = build(:user, password: 'Pa1!', password_confirmation: 'Pa1!')
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include('is too short (minimum is 8 characters)')
    end

    it 'accepts a strong password' do
      user = build(:user, password: 'Password1!', password_confirmation: 'Password1!')
      expect(user).to be_valid
    end
  end

  describe 'factory' do
    it 'creates a valid user' do
      user = build(:user)
      expect(user).to be_valid
    end

    it 'creates valid user with each role trait' do
      expect(build(:user, :viewer)).to be_valid
      expect(build(:user, :operator)).to be_valid
      expect(build(:user, :admin)).to be_valid
      expect(build(:user, :owner)).to be_valid
    end
  end
end
