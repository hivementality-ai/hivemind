# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :api_tokens, dependent: :destroy

  enum :role, { readonly: 0, operator: 1, admin: 2, owner: 3 }, default: :owner

  validates :role, presence: true
end
