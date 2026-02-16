# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Team, type: :model do
  describe 'associations' do
    it { should have_many(:agents).dependent(:destroy) }
    it { should have_many(:team_messages).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }

    it 'validates uniqueness of name' do
      create(:team, name: "Engineering")
      expect(build(:team, name: "Engineering")).not_to be_valid
    end
  end

  describe 'factory' do
    it 'creates a valid team' do
      team = build(:team)
      expect(team).to be_valid
    end
  end
end
