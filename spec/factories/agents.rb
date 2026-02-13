FactoryBot.define do
  factory :agent do
    name { "MyString" }
    role { "MyString" }
    team { nil }
    model_config { "" }
    tools_config { "" }
    status { 1 }
    workspace_path { "MyString" }
    system_prompt { "MyText" }
  end
end
