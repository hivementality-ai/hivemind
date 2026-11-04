# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/test_database_guard'

RSpec.describe TestDatabaseGuard do
  def violation(env) = described_class.new(env).violation

  it 'allows the CI test database' do
    expect(violation('RAILS_ENV' => 'test', 'DATABASE_URL' => 'postgres://hivemind:hivemind@localhost:5432/hivemind_test')).to be_nil
  end

  it 'allows a per-worktree test database' do
    expect(violation('DATABASE_URL' => 'postgres://localhost/hivemind_test_refresh_0_3')).to be_nil
  end

  it 'allows an unset DATABASE_URL' do
    expect(violation({})).to be_nil
  end

  it 'refuses the production compose database' do
    expect(violation('DATABASE_URL' => 'postgres://hivemind:hivemind@db:5432/hivemind_production')).to match(/production/)
  end

  it 'refuses a development database' do
    expect(violation('DATABASE_URL' => 'postgres://hivemind:hivemind@db:5432/hivemind_development')).to match(/not a test database/)
  end

  it 'refuses a production name even with a test suffix' do
    expect(violation('DATABASE_URL' => 'postgres://db/hivemind_production_test')).to match(/production/)
  end

  it 'refuses RAILS_ENV=production' do
    expect(violation('RAILS_ENV' => 'production')).to match(/RAILS_ENV/)
  end

  it 'refuses an unparseable URL' do
    expect(violation('DATABASE_URL' => 'postgres://')).to match(/parseable/)
  end

  it 'aborts with a message when enforcing an unsafe environment' do
    guard = described_class.new('DATABASE_URL' => 'postgres://db/hivemind_production')
    expect { guard.enforce! }.to raise_error(SystemExit).and output(/FATAL: Refusing/).to_stderr
  end
end
