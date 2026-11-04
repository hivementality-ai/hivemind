# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::SubsystemSchedule do
  # Reconciles for real against a stubbed cron API, after any Setting
  # fixtures have been written (their own reconcile is stubbed out globally).
  def reconcile
    allow(Sidekiq::Cron::Job).to receive(:create)
    allow(Sidekiq::Cron::Job).to receive(:destroy)
    allow(described_class).to receive(:reconcile!).and_call_original
    described_class.reconcile!
  end

  def created?(name)
    have_received(:create).with(hash_including(name: name))
  end

  def destroyed?(name)
    have_received(:destroy).with(name)
  end

  describe ".reconcile!" do
    context "on a fresh install with nothing switched on" do
      it "registers neither the heartbeat nor the remote access check" do
        reconcile

        expect(Sidekiq::Cron::Job).not_to created?("heartbeat")
        expect(Sidekiq::Cron::Job).not_to created?("remote_access_health_check")
        expect(Sidekiq::Cron::Job).to destroyed?("heartbeat")
        expect(Sidekiq::Cron::Job).to destroyed?("remote_access_health_check")
      end

      it "still registers the update check, which is on unless opted out" do
        reconcile

        expect(Sidekiq::Cron::Job).to created?("update_check")
      end
    end

    context "with the heartbeat enabled" do
      before { Setting.set("heartbeat", { "enabled" => true }.to_json) }

      it "registers the heartbeat" do
        reconcile

        expect(Sidekiq::Cron::Job).to created?("heartbeat")
      end
    end

    context "with the heartbeat saved but disabled" do
      before { Setting.set("heartbeat", { "enabled" => false }.to_json) }

      it "removes the heartbeat" do
        reconcile

        expect(Sidekiq::Cron::Job).not_to created?("heartbeat")
        expect(Sidekiq::Cron::Job).to destroyed?("heartbeat")
      end
    end

    context "with remote access configured" do
      before do
        Setting.set("canonical_host", "https://hive.example.com")
        Setting.set("remote_access_mode", "byo")
      end

      it "registers the health check" do
        reconcile

        expect(Sidekiq::Cron::Job).to created?("remote_access_health_check")
      end
    end

    context "with the update check opted out" do
      around do |example|
        original = ENV["UPDATE_CHECK_ENABLED"]
        ENV["UPDATE_CHECK_ENABLED"] = "false"
        example.run
      ensure
        ENV["UPDATE_CHECK_ENABLED"] = original
      end

      it "removes the update check" do
        reconcile

        expect(Sidekiq::Cron::Job).not_to created?("update_check")
        expect(Sidekiq::Cron::Job).to destroyed?("update_check")
      end
    end

    it "does not raise when Redis is unreachable" do
      reconcile
      allow(Sidekiq::Cron::Job).to receive(:create).and_raise(Redis::CannotConnectError)

      expect { described_class.reconcile! }.not_to raise_error
    end
  end

  describe "Setting changes" do
    %w[heartbeat canonical_host remote_access_mode].each do |key|
      it "reconcile the schedule when #{key} is saved" do
        allow(described_class).to receive(:reconcile!)

        Setting.set(key, "x")

        expect(described_class).to have_received(:reconcile!)
      end
    end

    it "leave the schedule alone for an unrelated key" do
      allow(described_class).to receive(:reconcile!)

      Setting.set("something_else", "x")

      expect(described_class).not_to have_received(:reconcile!)
    end
  end
end
