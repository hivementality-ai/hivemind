# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TranscriptArchive, type: :model do
  describe 'associations' do
    it { should belong_to(:session) }
  end

  describe 'validations' do
    it { should validate_presence_of(:transcript) }
  end

  describe 'default values' do
    it 'initializes archived_at to current time' do
      archive = TranscriptArchive.new
      expect(archive.archived_at).to be_within(1.second).of(Time.current)
    end
  end

  describe 'factory' do
    it 'creates a valid transcript archive' do
      expect(build(:transcript_archive)).to be_valid
    end

    it 'creates valid archive with large trait' do
      expect(build(:transcript_archive, :large)).to be_valid
    end
  end
end
