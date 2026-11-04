# frozen_string_literal: true

namespace :hivemind do
  desc "Print COMPOSE_PROFILES=... for the channel services enabled channels need (used by `hivemind update`)"
  task compose_profiles: :environment do
    puts "COMPOSE_PROFILES=#{Channels::ComposeProfiles.needed.join(',')}"
  end
end
