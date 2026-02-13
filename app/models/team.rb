# frozen_string_literal: true

class Team < ApplicationRecord
  has_many :agents, dependent: :destroy
  has_many :team_messages, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
