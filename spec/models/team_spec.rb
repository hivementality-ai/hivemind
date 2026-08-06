# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Team, type: :model do
  describe 'associations' do
    it { should have_many(:agents).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }

    it 'validates uniqueness of name' do
      create(:team, name: "Engineering")
      expect(build(:team, name: "Engineering")).not_to be_valid
    end
  end

  describe 'callbacks' do
    it 'triggers rebuild_soul when custom_soul changes' do
      team = create(:team)
      expect(Teams::BuildSoul).to receive(:call).with(team: team)
      team.update!(custom_soul: "Be creative and bold")
    end

    it 'triggers rebuild_soul when name changes' do
      team = create(:team)
      expect(Teams::BuildSoul).to receive(:call).with(team: team)
      team.update!(name: "New Name #{SecureRandom.hex(4)}")
    end

    it 'does not trigger rebuild_soul when no tracked fields change' do
      team = create(:team)
      expect(Teams::BuildSoul).not_to receive(:call)
      team.save!
    end
  end

  describe 'factory' do
    it 'creates a valid team' do
      team = build(:team)
      expect(team).to be_valid
    end
  end
end
