FactoryBot.define do
  factory :api_token do
    user { nil }
    name { "MyString" }
    token_digest { "MyString" }
    scopes { "" }
    last_used_at { "2026-02-13 10:49:54" }
    expires_at { "2026-02-13 10:49:54" }
    revoked_at { "2026-02-13 10:49:54" }
  end
end
