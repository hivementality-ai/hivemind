# frozen_string_literal: true

namespace :hivemind do
  desc "Run Hivemind system diagnostics"
  task doctor: :environment do
    checks = Hivemind::Doctor.run_all
    Hivemind::Doctor.print_results(checks)

    exit(1) if checks.any? { |c| c[:status] == :error }
  end
end
