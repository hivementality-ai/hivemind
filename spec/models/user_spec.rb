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
