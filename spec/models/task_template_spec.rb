# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskTemplate, type: :model do
  describe "associations" do
    it { should have_many(:task_hooks).dependent(:destroy) }
    it { should have_many(:tasks).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:task_template) }

    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_inclusion_of(:default_priority).in_array(Task::PRIORITIES) }
  end
end
