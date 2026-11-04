# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

# Runs bin/hivemind's update flow against PATH shims for docker, git, curl
# and sleep, so no real containers or network are touched.
RSpec.describe "bin/hivemind update" do
  let(:cli) { File.expand_path("../../bin/hivemind", __dir__) }
  let(:dir) { Dir.mktmpdir("hivemind-cli") }
  let(:shims) { File.join(dir, "shims") }
  let(:calls) { File.join(dir, "calls.log") }

  before do
    FileUtils.mkdir_p(shims)
    File.write(File.join(dir, "docker-compose.yml"), "services: {}\n")
    write_shim("git", "exit 0")
    write_shim("sleep", "exit 0")
    write_shim("curl", 'if [ "${SHIM_HEALTHY:-1}" = 1 ]; then exit 0; else exit 22; fi')
    write_shim("docker", <<~'SH')
      echo "docker $*" >> "$SHIM_CALLS"
      case "$*" in
        "compose ps"*) [ "${SHIM_DB_RUNNING:-1}" = 1 ] && echo db; exit 0 ;;
        *"pg_dump"*) [ "${SHIM_DUMP_OK:-1}" = 1 ] && echo "-- dump" ; [ "${SHIM_DUMP_OK:-1}" = 1 ]; exit $? ;;
        *"db:migrate"*) [ "${SHIM_MIGRATE_OK:-1}" = 1 ] || echo "PG::UndefinedTable boom" >&2; [ "${SHIM_MIGRATE_OK:-1}" = 1 ]; exit $? ;;
        *"hivemind:compose_profiles"*)
          [ "${SHIM_PROFILES_OK:-1}" = 1 ] || exit 1
          echo "noise line"; echo "COMPOSE_PROFILES=${SHIM_PROFILES-}"; exit 0 ;;
        *) exit 0 ;;
      esac
    SH
  end

  after { FileUtils.remove_entry(dir) }

  def write_shim(name, body)
    path = File.join(shims, name)
    File.write(path, "#!/usr/bin/env bash\n#{body}\n")
    File.chmod(0o755, path)
  end

  def run_cli(script, env = {})
    full = {
      "PATH" => "#{shims}:#{ENV.fetch('PATH')}", "HIVEMIND_DIR" => dir,
      "SHIM_CALLS" => calls, "HIVEMIND_HEALTH_TIMEOUT" => "2", "HIVEMIND_HEALTH_INTERVAL" => "1"
    }.merge(env)
    out, status = Open3.capture2e(full, "bash", "-c", "source #{cli}; #{script}")
    [ out, status ]
  end

  def docker_calls
    File.exist?(calls) ? File.read(calls) : ""
  end

  def backups
    Dir.glob(File.join(dir, "backups", "pre-update-*.sql"))
  end

  describe "a healthy update" do
    it "backs up first, pulls every published image, restarts and reports healthy" do
      out, status = run_cli("cmd_update")

      expect(status).to be_success
      expect(backups.size).to eq(1)
      expect(out).to include("Database backed up")
      expect(docker_calls).to include("pull app workspace connector sdk-proxy browser-sidecar")
      expect(docker_calls.index("pg_dump")).to be < docker_calls.index("db:migrate")
      expect(docker_calls).to include("up -d --force-recreate")
      expect(out).to include("and healthy")
    end
  end

  describe "a failing migration" do
    it "shows the error, skips the recreate and points at the backup" do
      out, status = run_cli("cmd_update", "SHIM_MIGRATE_OK" => "0")

      expect(status).not_to be_success
      expect(out).to include("PG::UndefinedTable boom")
      expect(out).to include(backups.first)
      expect(out).to include("psql -U hivemind")
      expect(docker_calls).not_to include("up -d")
    end
  end

  describe "a failing backup" do
    it "aborts before pulling or migrating" do
      out, status = run_cli("cmd_update", "SHIM_DUMP_OK" => "0")

      expect(status).not_to be_success
      expect(out).to include("Database backup failed")
      expect(backups).to be_empty
      expect(docker_calls).not_to include("db:migrate")
    end
  end

  describe "an app that never turns healthy" do
    it "warns with the logs hint and exits non-zero" do
      out, status = run_cli("cmd_update", "SHIM_HEALTHY" => "0")

      expect(status).not_to be_success
      expect(out).to include("did not answer /up")
      expect(out).to include("hivemind logs app")
      expect(out).not_to include("and healthy")
    end
  end

  describe "backup retention" do
    it "keeps only the newest HIVEMIND_BACKUPS_KEEP backups" do
      FileUtils.mkdir_p(File.join(dir, "backups"))
      (1..4).each do |i|
        file = File.join(dir, "backups", "pre-update-2020010#{i}-000000.sql")
        File.write(file, "old")
        File.utime(Time.now - (100 - i), Time.now - (100 - i), file)
      end

      run_cli("backup_database_before_update", "HIVEMIND_BACKUPS_KEEP" => "2")

      expect(backups.size).to eq(2)
      expect(backups.map { |f| File.basename(f) }).not_to include("pre-update-20200101-000000.sql")
    end
  end

  describe "with no running database" do
    it "skips the backup and carries on" do
      out, status = run_cli("backup_database_before_update; echo rc=$?", "SHIM_DB_RUNNING" => "0")

      expect(status).to be_success
      expect(out).to include("skipping backup")
      expect(out).to include("rc=0")
      expect(backups).to be_empty
    end
  end

  describe "channel service profiles" do
    let(:env_file) { File.join(dir, ".env") }

    before { File.write(env_file, "APP_PORT=3000\n") }

    def profiles_line
      File.read(env_file)[/^COMPOSE_PROFILES=.*$/]
    end

    it "persists the profiles an existing channel user needs before recreating the stack" do
      out, status = run_cli("cmd_update", "SHIM_PROFILES" => "channels,signal")

      expect(status).to be_success
      expect(profiles_line).to eq("COMPOSE_PROFILES=channels,signal")
      expect(docker_calls.index("hivemind:compose_profiles")).to be < docker_calls.index("up -d --force-recreate")
      expect(out).to include("and healthy")
    end

    it "merges with profiles already in .env without duplicating, and is idempotent" do
      File.write(env_file, "COMPOSE_PROFILES=tunnel,channels\n")

      2.times { run_cli("cmd_update", "SHIM_PROFILES" => "channels,signal") }

      expect(File.read(env_file).scan("COMPOSE_PROFILES=").size).to eq(1)
      expect(profiles_line).to eq("COMPOSE_PROFILES=tunnel,channels,signal")
    end

    it "leaves .env alone when no channel needs a service" do
      run_cli("cmd_update", "SHIM_PROFILES" => "")

      expect(profiles_line).to be_nil
    end

    it "keeps both services enabled when the app cannot answer" do
      out, status = run_cli("cmd_update", "SHIM_PROFILES_OK" => "0")

      expect(status).to be_success
      expect(out).to include("keeping channel services enabled")
      expect(profiles_line).to eq("COMPOSE_PROFILES=channels,signal")
    end
  end
end
