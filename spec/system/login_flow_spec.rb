# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Login flow", type: :system do
  let!(:user) do
    create(:user, email: "tester@hivemind.dev", password: "Password1!", password_confirmation: "Password1!")
  end

  before do
    Setting.set("setup_complete", "true")
  end

  it "logs in with valid credentials and reaches the dashboard" do
    visit root_path

    expect(page).to have_content("Sign in to Hivemind")

    fill_in "user_email", with: "tester@hivemind.dev"
    fill_in "user_password", with: "Password1!"
    click_button "Sign in"

    expect(page).to have_content("Mission Control")
  end

  it "rejects invalid credentials and stays on login" do
    visit root_path

    fill_in "user_email", with: "tester@hivemind.dev"
    fill_in "user_password", with: "wrongpassword"
    click_button "Sign in"

    expect(page).to have_content("Sign in to Hivemind")
  end

  it "redirects unauthenticated users to login" do
    visit dashboard_path

    expect(page).to have_content("Sign in to Hivemind")
  end
end
