# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Load all seed files from db/seeds/
# Tools must load before skills so SkillTool bindings resolve correctly.
seed_files = Dir[Rails.root.join("db/seeds/**/*.rb")].sort
tools_file = seed_files.find { |f| f.end_with?("tools.rb") }
if tools_file
  seed_files.delete(tools_file)
  seed_files.unshift(tools_file)
end
seed_files.each { |f| load f }
