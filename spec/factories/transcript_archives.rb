FactoryBot.define do
  factory :transcript_archive do
    association :session
    transcript do
      [
        { role: "user", content: "Hello", timestamp: 2.hours.ago.iso8601 },
        { role: "assistant", content: "Hi!", timestamp: 2.hours.ago.iso8601 }
      ]
    end
    archived_at { Time.current }

    trait :large do
      transcript do
        50.times.map do |i|
          { role: i.even? ? "user" : "assistant", content: "Message #{i}", timestamp: (50 - i).minutes.ago.iso8601 }
        end
      end
    end
  end
end
