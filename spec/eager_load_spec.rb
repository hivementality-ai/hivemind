# frozen_string_literal: true

require "rails_helper"

# Production boots with eager loading, so a class-body error that dev and
# lazily-loading specs never trip (e.g. skip_before_action naming a callback
# an ancestor already removed) crashes the server at startup. Loading every
# constant here makes that a CI failure instead of a production outage.
RSpec.describe "application eager loading" do
  it "loads every autoloadable constant without raising" do
    expect { Rails.application.eager_load! }.not_to raise_error
  end
end
