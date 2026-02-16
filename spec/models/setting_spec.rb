# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Setting, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:key) }

    describe 'uniqueness of key' do
      let!(:existing_setting) { create(:setting, key: 'unique_key') }

      it 'rejects duplicate keys' do
        new_setting = build(:setting, key: 'unique_key')
        expect(new_setting).not_to be_valid
        expect(new_setting.errors[:key]).to include('has already been taken')
      end
    end
  end

  describe '.get' do
    context 'when setting exists' do
      let!(:setting) { create(:setting, key: 'app_name', value: 'MyApp') }

      it 'returns the value' do
        expect(Setting.get('app_name')).to eq('MyApp')
      end
    end

    context 'when setting does not exist' do
      it 'returns nil' do
        expect(Setting.get('nonexistent_key')).to be_nil
      end
    end

    context 'with different value types' do
      let!(:string_setting) { create(:setting, key: 'str_key', value: 'string_value') }
      let!(:json_setting) do
        create(:setting, key: 'json_key',
               value: { data: 'value' }.to_json)
      end
      let!(:numeric_setting) { create(:setting, key: 'num_key', value: '42') }

      it 'retrieves string values' do
        expect(Setting.get('str_key')).to eq('string_value')
      end

      it 'retrieves JSON values as strings' do
        expect(Setting.get('json_key')).to eq({ data: 'value' }.to_json)
      end

      it 'retrieves numeric values as strings' do
        expect(Setting.get('num_key')).to eq('42')
      end
    end
  end

  describe '.set' do
    context 'when setting does not exist' do
      it 'creates a new setting' do
        expect {
          Setting.set('new_key', 'new_value')
        }.to change(Setting, :count).by(1)
      end

      it 'persists the setting with correct values' do
        Setting.set('new_key', 'new_value')
        setting = Setting.find_by(key: 'new_key')
        expect(setting.value).to eq('new_value')
      end
    end

    context 'when setting already exists' do
      let!(:existing_setting) { create(:setting, key: 'existing_key', value: 'old_value') }

      it 'updates the existing setting' do
        Setting.set('existing_key', 'new_value')
        expect(existing_setting.reload.value).to eq('new_value')
      end

      it 'does not create a new setting' do
        expect {
          Setting.set('existing_key', 'new_value')
        }.not_to change(Setting, :count)
      end
    end

    context 'with different value types' do
      it 'stores string values' do
        Setting.set('str_setting', 'string_value')
        expect(Setting.get('str_setting')).to eq('string_value')
      end

      it 'stores numeric values' do
        Setting.set('num_setting', 123)
        expect(Setting.get('num_setting')).to eq('123')
      end

      it 'stores JSON values' do
        data = { nested: { structure: true } }
        Setting.set('json_setting', data.to_json)
        expect(Setting.get('json_setting')).to eq(data.to_json)
      end
    end

    context 'idempotency' do
      it 'can be called multiple times with same result' do
        Setting.set('idempotent_key', 'value1')
        Setting.set('idempotent_key', 'value1')
        expect(Setting.where(key: 'idempotent_key').count).to eq(1)
      end
    end
  end

  describe 'factory' do
    it 'creates a valid setting' do
      expect(build(:setting)).to be_valid
    end

    it 'creates valid settings with traits' do
      expect(build(:setting, :with_string_value)).to be_valid
      expect(build(:setting, :with_json_value)).to be_valid
      expect(build(:setting, :with_numeric_value)).to be_valid
      expect(build(:setting, :with_boolean_value)).to be_valid
    end
  end
end
