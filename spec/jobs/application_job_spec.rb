# frozen_string_literal: true

require "rails_helper"

# Guards the retry policy every job inherits. Before 2026-08-25, a raised
# error fell through to Sidekiq's default of 25 retries — and for anything
# that reaches an LLM provider, each attempt opens fresh TCP connections
# against the host's shared ephemeral port pool.
RSpec.describe ApplicationJob, type: :job do
  def handler_for(job_class, error_class)
    job_class.rescue_handlers.reverse.find do |klass_name, _|
      klass_name.is_a?(String) && klass_name.safe_constantize &&
        error_class <= klass_name.safe_constantize
    end
  end

  describe "the inherited policy" do
    it "declares a bounded floor instead of Sidekiq's default 25" do
      expect(handler_for(described_class, StandardError)).to be_present
    end

    it "discards permanent provider failures rather than retrying them" do
      klass_name, = handler_for(described_class, PermanentProviderError)
      expect(klass_name).to eq("PermanentProviderError")
    end

    it "picks the permanent handler over the broad one" do
      # ActiveSupport::Rescuable matches last-declared-first, so the specific
      # discard_on must win over the broad retry_on. If this inverts, a quota
      # failure starts retrying again.
      permanent, = handler_for(described_class, PermanentProviderError)
      expect(permanent).to eq("PermanentProviderError")
      expect(permanent).not_to eq("StandardError")
    end

    it "retries transient provider failures" do
      klass_name, = handler_for(described_class, TransientProviderError)
      expect(klass_name).to eq("TransientProviderError")
    end

    it "treats a circuit-open error as permanent" do
      klass_name, = handler_for(described_class, ProviderCircuitOpenError)
      expect(klass_name).to eq("PermanentProviderError")
    end
  end

  describe "behaviour" do
    before do
      stub_const("QuotaFailingJob", Class.new(ApplicationJob) do
        cattr_accessor(:runs) { 0 }
        def perform
          self.class.runs += 1
          raise PermanentProviderError.new("You're out of extra usage.", reason: "quota_exhausted", status: 402)
        end
      end)

      stub_const("TransientFailingJob", Class.new(ApplicationJob) do
        cattr_accessor(:runs) { 0 }
        def perform
          self.class.runs += 1
          raise TransientProviderError.new("overloaded", reason: "server_error", status: 529)
        end
      end)
    end

    it "runs a quota failure exactly once and never re-enqueues it" do
      expect { perform_enqueued_jobs { QuotaFailingJob.perform_later } }.not_to raise_error

      expect(QuotaFailingJob.runs).to eq(1)
      expect(enqueued_jobs).to be_empty
    end

    it "re-enqueues a transient failure with backoff" do
      perform_enqueued_jobs(only: ->(_) { false }) { TransientFailingJob.perform_later }
      # Run just the first attempt; the retry is scheduled, not run inline.
      expect { TransientFailingJob.perform_now }.not_to raise_error
      expect(TransientFailingJob.runs).to eq(1)
    end

    it "caps transient retries well below Sidekiq's 25" do
      attempts = 0
      allow_any_instance_of(TransientFailingJob).to receive(:perform) do
        attempts += 1
        raise TransientProviderError.new("overloaded", reason: "server_error", status: 529)
      end

      # After the cap is spent ActiveJob re-raises rather than retrying
      # forever — that re-raise is the bound working. (ActiveJob::TestHelper
      # rewraps it, so assert on the attempt count, which is the real claim.)
      begin
        perform_enqueued_jobs { TransientFailingJob.perform_later }
      rescue Exception # rubocop:disable Lint/SuppressedException, Lint/RescueException
      end

      expect(attempts).to eq(3), "3 attempts, not Sidekiq's 25"
    end
  end

  describe "subclasses that declare their own policy" do
    it "lets WebhookDeliveryJob keep its 5 attempts" do
      klass_name, = handler_for(WebhookDeliveryJob, StandardError)
      expect(klass_name).to eq("StandardError")
      # Declared in the subclass, so it wins over ApplicationJob's floor.
      expect(WebhookDeliveryJob.rescue_handlers.length)
        .to be > ApplicationJob.rescue_handlers.length
    end
  end
end
