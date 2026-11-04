# frozen_string_literal: true

require 'uri'

# Decides whether the database RSpec is about to use is safe to truncate.
# Plain Ruby so it can run before Rails boots and be tested without a database.
class TestDatabaseGuard
  TEST_NAME = /_test(_[A-Za-z0-9_]+)?\z/
  PRODUCTION_NAME = /production/i

  # @param env [Hash, #[]] process environment
  def initialize(env = ENV)
    @env = env
  end

  # @return [String, nil] the reason the run must be refused, or nil when safe
  def violation
    return "RAILS_ENV is #{@env['RAILS_ENV']}" if @env['RAILS_ENV'] == 'production'

    url = @env['DATABASE_URL'].to_s
    return nil if url.empty?

    name = database_name(url)
    return 'DATABASE_URL is not a parseable database URL' if name.nil?
    return "DATABASE_URL points at production database #{name.inspect}" if name.match?(PRODUCTION_NAME)
    return "DATABASE_URL database #{name.inspect} is not a test database (name must end in _test or _test_<suffix>)" unless name.match?(TEST_NAME)

    nil
  end

  # Aborts the process with a clear message when the database is unsafe.
  def enforce!
    reason = violation
    return unless reason

    abort("FATAL: Refusing to run specs: #{reason}. RSpec truncates the database. " \
          'Point DATABASE_URL at a *_test database; never run RSpec in the production container.')
  end

  private

  def database_name(url)
    path = URI.parse(url).path.to_s.delete_prefix('/')
    path.empty? ? nil : path
  rescue URI::InvalidURIError
    nil
  end
end
