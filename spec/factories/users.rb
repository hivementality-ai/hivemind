FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "Password1!" }
    password_confirmation { "Password1!" }
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
