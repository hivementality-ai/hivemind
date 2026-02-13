# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::GatewayExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  describe '#call' do
    context 'with status action' do
      let(:input) { { "action" => "status" } }

      before do
        # Mock database connection
        allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)
        
        # Mock Redis
        redis_mock = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis_mock)
        allow(redis_mock).to receive(:ping).and_return("PONG")
        
        # Mock model counts
        allow(Agent).to receive_message_chain(:visible, :count).and_return(5)
        allow(Agent).to receive_message_chain(:visible, :enabled, :count).and_return(3)
        allow(Team).to receive(:count).and_return(2)
        allow(Session).to receive(:count).and_return(10)
        allow(Tool).to receive_message_chain(:where, :count).and_return(8)
        allow(UsageRecord).to receive(:count).and_return(100)
        
        # Mock provider configs
        provider1 = instance_double(ProviderConfig, adapter_type: 'openai', enabled?: true)
        provider2 = instance_double(ProviderConfig, adapter_type: 'anthropic', enabled?: false)
        allow(ProviderConfig).to receive(:all).and_return([provider1, provider2])
      end

      it 'returns platform status' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("🐝 Hivemind Platform Status")
        expect(result.data[:output]).to include("Ruby: #{RUBY_VERSION}")
        expect(result.data[:output]).to include("Rails: #{Rails.version}")
        expect(result.data[:output]).to include("Environment: #{Rails.env}")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'shows database status' do
        result = executor.call
        expect(result.data[:output]).to include("PostgreSQL: ✅ Connected")
      end

      it 'shows Redis status when connected' do
        result = executor.call
        expect(result.data[:output]).to include("Redis: ✅ Connected")
      end

      it 'shows model counts' do
        result = executor.call
        expect(result.data[:output]).to include("Agents: 5 (3 enabled)")
        expect(result.data[:output]).to include("Teams: 2")
        expect(result.data[:output]).to include("Sessions: 10")
        expect(result.data[:output]).to include("Tools: 8")
        expect(result.data[:output]).to include("Usage Records: 100")
      end

      it 'shows provider status' do
        result = executor.call
        expect(result.data[:output]).to include("openai: ✅")
        expect(result.data[:output]).to include("anthropic: ⏸️")
      end

      context 'when database is down' do
        before do
          allow(ActiveRecord::Base.connection).to receive(:active?).and_raise(StandardError)
        end

        it 'shows database as down' do
          result = executor.call
          expect(result.data[:output]).to include("PostgreSQL: ❌ Down")
        end
      end

      context 'when Redis is down' do
        before do
          allow(Redis).to receive(:new).and_raise(StandardError)
        end

        it 'shows Redis as down' do
          result = executor.call
          expect(result.data[:output]).to include("Redis: ❌ Down")
        end
      end

      context 'with custom Redis URL' do
        before do
          allow(ENV).to receive(:[]).with("REDIS_URL").and_return("redis://custom:6379")
        end

        it 'uses custom Redis URL' do
          result = executor.call
          expect(Redis).to have_received(:new).with(url: "redis://custom:6379")
        end
      end
    end

    context 'with restart action' do
      context 'restarting Rails' do
        let(:input) { { "action" => "restart", "service" => "rails" } }

        before do
          allow(FileUtils).to receive(:touch)
          allow(Rails).to receive(:root).and_return(Pathname.new("/app"))
        end

        it 'triggers Rails restart' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Rails restart triggered")
          expect(result.data[:exit_code]).to eq(0)
          expect(FileUtils).to have_received(:touch).with(Pathname.new("/app/tmp/restart.txt"))
        end
      end

      context 'restarting Sidekiq' do
        let(:input) { { "action" => "restart", "service" => "sidekiq" } }

        it 'returns message about Docker CLI' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Sidekiq restart not supported")
          expect(result.data[:output]).to include("Docker CLI")
          expect(result.data[:exit_code]).to eq(0)
        end
      end

      context 'with invalid service' do
        let(:input) { { "action" => "restart", "service" => "invalid" } }

        it 'returns failure with allowed services' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to include("Can only restart: rails, sidekiq")
        end
      end

      context 'without service specified' do
        let(:input) { { "action" => "restart" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to include("Can only restart: rails, sidekiq")
        end
      end

      context 'with empty service' do
        let(:input) { { "action" => "restart", "service" => "  " } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to include("Can only restart: rails, sidekiq")
        end
      end
    end

    context 'with config action' do
      let(:input) { { "action" => "config" } }

      before do
        allow(ActiveRecord::Base.connection).to receive(:current_database).and_return('hivemind_test')
        
        # Mock Sidekiq::Cron if defined
        if defined?(Sidekiq::Cron)
          job1 = instance_double('Sidekiq::Cron::Job', name: 'daily_cleanup', cron: '0 2 * * *', klass: 'CleanupJob')
          job2 = instance_double('Sidekiq::Cron::Job', name: 'hourly_sync', cron: '0 * * * *', klass: 'SyncJob')
          allow(Sidekiq::Cron::Job).to receive(:all).and_return([job1, job2])
        end

        # Mock settings
        setting1 = instance_double(Setting, key: 'app_name', value: 'Hivemind')
        setting2 = instance_double(Setting, key: 'max_sessions', value: 100)
        allow(Setting).to receive(:all).and_return([setting1, setting2])
      end

      it 'shows configuration details' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Database: hivemind_test")
        expect(result.data[:output]).to include("Redis: not set")  # Default when no ENV var
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'shows settings' do
        result = executor.call
        expect(result.data[:output]).to include("app_name: Hivemind")
        expect(result.data[:output]).to include("max_sessions: 100")
      end

      context 'with Redis URL configured' do
        before do
          allow(ENV).to receive(:[]).with("REDIS_URL").and_return("redis://localhost:6379")
        end

        it 'shows Redis URL' do
          result = executor.call
          expect(result.data[:output]).to include("Redis: redis://localhost:6379")
        end
      end

      context 'when Sidekiq::Cron is available' do
        before do
          skip unless defined?(Sidekiq::Cron)
        end

        it 'shows cron jobs' do
          result = executor.call
          expect(result.data[:output]).to include("daily_cleanup — 0 2 * * * (CleanupJob)")
          expect(result.data[:output]).to include("hourly_sync — 0 * * * * (SyncJob)")
        end
      end

      context 'with long setting values' do
        before do
          long_setting = instance_double(Setting, key: 'long_value', value: 'x' * 100)
          allow(Setting).to receive(:all).and_return([long_setting])
        end

        it 'truncates long values' do
          result = executor.call
          long_line = result.data[:output].lines.find { |line| line.include?('long_value:') }
          expect(long_line.length).to be <= 80  # key + ": " + 60 chars + some margin
        end
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("status, restart, config")
      end
    end

    context 'when database operation fails' do
      let(:input) { { "action" => "status" } }

      before do
        allow(Agent).to receive_message_chain(:visible, :count).and_raise(StandardError.new("Database error"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Gateway error: Database error")
      end
    end

    context 'when FileUtils.touch fails during restart' do
      let(:input) { { "action" => "restart", "service" => "rails" } }

      before do
        allow(FileUtils).to receive(:touch).and_raise(Errno::EACCES.new("Permission denied"))
        allow(Rails).to receive(:root).and_return(Pathname.new("/app"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Gateway error: Permission denied")
      end
    end

    context 'when ActiveRecord connection fails during config' do
      let(:input) { { "action" => "config" } }

      before do
        allow(ActiveRecord::Base.connection).to receive(:current_database).and_raise(StandardError.new("Connection lost"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Gateway error: Connection lost")
      end
    end
  end
end