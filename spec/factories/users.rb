FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    role { :viewer }

    trait :viewer do
      role { :viewer }
    end

    trait :operator do
      role { :operator }
    end

    trait :admin do
      role { :admin }
    end

    trait :owner do
      role { :owner }
    end
  end
end
