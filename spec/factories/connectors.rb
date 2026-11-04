# frozen_string_literal: true

FactoryBot.define do
  factory :connector do
    sequence(:name) { |n| "Widgets API #{n}" }
    sequence(:slug) { |n| "widgets_#{n}" }
    description { "Widget inventory" }
    base_url { "https://api.widgets.test/v1" }
    auth_scheme { "none" }
    auth_config { {} }
    enabled { true }
    operations do
      [
        {
          "name" => "get_widget",
          "description" => "Fetch one widget",
          "method" => "GET",
          "path" => "/widgets/{id}",
          "params" => {
            "type" => "object",
            "properties" => { "id" => { "type" => "string" }, "verbose" => { "type" => "boolean" } },
            "required" => [ "id" ]
          },
          "read_only" => true
        },
        {
          "name" => "create_widget",
          "description" => "Create a widget",
          "method" => "POST",
          "path" => "/widgets",
          "params" => { "type" => "object", "properties" => { "title" => { "type" => "string" } }, "required" => [ "title" ] },
          "read_only" => false
        }
      ]
    end

    trait :bearer do
      auth_scheme { "bearer" }
      auth_config { { "secret" => "vault:widgets/token" } }
    end
  end
end
