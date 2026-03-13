# frozen_string_literal: true

class Team < ApplicationRecord
  has_many :agents, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :team_messages, dependent: :destroy
  has_many :team_chat_sessions, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  after_save :rebuild_soul, if: -> { saved_change_to_name? || saved_change_to_description? || saved_change_to_custom_soul? }

  private

  def rebuild_soul
    Teams::BuildSoul.call(team: self)
  end
end
