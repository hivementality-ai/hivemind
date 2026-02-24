# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Returning user login", type: :system do
  let!(:user) do
    create(:user, email: "returning@hivemind.dev", password: "Password1!", password_confirmation: "Password1!")
  end

  before do
    Setting.set("setup_complete", "true")
  end

  it "signs in an existing user and lands on the dashboard" do
    visit new_user_session_path

    fill_in "user_email", with: "returning@hivemind.dev"
    fill_in "user_password", with: "Password1!"
    click_button "Sign in"

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content("Mission Control")
  end
end
