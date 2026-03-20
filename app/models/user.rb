# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :api_tokens, dependent: :destroy
  has_many :projects

  enum :role, { viewer: 0, operator: 1, admin: 2, owner: 3 }, default: :owner

  validates :role, presence: true

  validate :password_complexity, if: -> { password.present? }

  private

  def password_complexity
    return if password.blank?

    unless password.match?(/[A-Z]/)
      errors.add(:password, "must include at least one uppercase letter")
    end

    unless password.match?(/[a-z]/)
      errors.add(:password, "must include at least one lowercase letter")
    end

    unless password.match?(/\d/)
      errors.add(:password, "must include at least one digit")
    end

    unless password.match?(/[^A-Za-z0-9]/)
      errors.add(:password, "must include at least one special character")
    end
  end
end
