# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::CronConfirmation do
  let(:agent) { create(:agent, name: "TestAgent") }

  describe ".generate_explanation" do
    it "generates a pending confirmation with token" do
      result = Agents::CronConfirmation.generate_explanation(
        agent: agent,
        name: "Blog Post Auto",
        schedule: "0 9 * * 1",
        job_class: "BlogPostJob",
        job_params: { model: "sonnet" },
        description_hint: "Generate weekly blog post"
      )

      expect(result[:status]).to eq("pending_confirmation")
      expect(result[:confirmation_id]).to be_present
      expect(result[:explanation]).to include(
        task: "Generate weekly blog post",
        frequency: "Every Monday at 09:00",
        agent: "TestAgent"
      )
      expect(result[:expires_in_minutes]).to eq(15)
    end

    it "generates cost estimation for Sonnet model" do
      result = Agents::CronConfirmation.generate_explanation(
        agent: agent,
        name: "Test Task",
        schedule: "0 9 * * *",
        job_class: "BlogPostJob",
        job_params: { model: "sonnet" }
      )

      expect(result[:explanation][:estimated_cost]).to include("$0.50")
      expect(result[:explanation][:estimated_cost]).to include("Sonnet")
    end

    it "generates cost estimation for Haiku model" do
      result = Agents::CronConfirmation.generate_explanation(
        agent: agent,
        name: "Test Task",
        schedule: "0 9 * * *",
        job_class: "NotificationJob",
        job_params: { model: "haiku" }
      )

      expect(result[:explanation][:estimated_cost]).to include("$0.05")
      expect(result[:explanation][:estimated_cost]).to include("Haiku")
    end

    it "generates cost estimation for Opus model" do
      result = Agents::CronConfirmation.generate_explanation(
        agent: agent,
        name: "Test Task",
        schedule: "0 9 * * *",
        job_class: "ReportGenerationJob",
        job_params: { model: "opus" }
      )

      expect(result[:explanation][:estimated_cost]).to include("$2.00")
      expect(result[:explanation][:estimated_cost]).to include("Opus")
    end

    it "uses description_hint when provided" do
      result = Agents::CronConfirmation.generate_explanation(
        agent: agent,
        name: "Custom Task",
        schedule: "0 9 * * *",
        job_class: "CustomJob",
        job_params: {},
        description_hint: "Custom description from hint"
      )

      expect(result[:explanation][:task]).to eq("Custom description from hint")
    end

    it "humanizes job class when no hint provided" do
      result = Agents::CronConfirmation.generate_explanation(
        agent: agent,
        name: "Task",
        schedule: "0 9 * * *",
        job_class: "BlogPostJob",
        job_params: {}
      )

      expect(result[:explanation][:task]).to eq("Blog post")
    end

    it "stores confirmation in Redis" do
      expect_any_instance_of(Agents::CronConfirmation).to receive(:store_pending_confirmation).once

      result = Agents::CronConfirmation.generate_explanation(
        agent: agent,
        name: "Test",
        schedule: "0 9 * * *",
        job_class: "TestJob",
        job_params: {}
      )

      expect(result[:confirmation_id]).to be_present
      expect(result[:status]).to eq("pending_confirmation")
    end
  end

  describe ".confirm_and_persist" do
    let(:confirmation_service) { Agents::CronConfirmation.new(agent: agent) }

    before do
      # Mock Redis storage
      allow_any_instance_of(Agents::CronConfirmation)
        .to receive(:retrieve_pending_confirmation)
        .and_return(
          "agent_id" => agent.id,
          "name" => "Test Task",
          "schedule" => "0 9 * * 1",
          "job_class" => "TestJob",
          "job_params" => { "param" => "value" },
          "description_hint" => "Test description"
        )
    end

    it "creates a scheduled task from pending confirmation" do
      result = Agents::CronConfirmation.confirm_and_persist(
        confirmation_id: "valid_token",
        agent: agent
      )

      expect(result[:status]).to eq("created")
      expect(result[:task_id]).to be_present
      expect(result[:message]).to include("scheduled ✅")
    end

    it "returns error when confirmation expired" do
      allow_any_instance_of(Agents::CronConfirmation)
        .to receive(:retrieve_pending_confirmation)
        .and_return(nil)

      result = Agents::CronConfirmation.confirm_and_persist(
        confirmation_id: "expired_token",
        agent: agent
      )

      expect(result[:status]).to eq("error")
      expect(result[:message]).to include("expired or invalid")
    end

    it "returns error when agent doesn't match" do
      other_agent = create(:agent, name: "OtherAgent")

      allow_any_instance_of(Agents::CronConfirmation)
        .to receive(:retrieve_pending_confirmation)
        .and_return(
          "agent_id" => create(:agent).id,
          "name" => "Test",
          "schedule" => "0 9 * * *",
          "job_class" => "TestJob",
          "job_params" => {}
        )

      result = Agents::CronConfirmation.confirm_and_persist(
        confirmation_id: "token",
        agent: other_agent
      )

      expect(result[:status]).to eq("error")
      expect(result[:message]).to include("Agent mismatch")
    end

    it "sets task to active confirmation status" do
      allow_any_instance_of(Agents::CronConfirmation)
        .to receive(:delete_pending_confirmation) { }

      result = Agents::CronConfirmation.confirm_and_persist(
        confirmation_id: "valid_token",
        agent: agent
      )

      task = ScheduledTask.find(result[:task_id])
      expect(task.confirmation_status).to eq("active")
    end

    it "enables the task" do
      allow_any_instance_of(Agents::CronConfirmation)
        .to receive(:delete_pending_confirmation) { }

      result = Agents::CronConfirmation.confirm_and_persist(
        confirmation_id: "valid_token",
        agent: agent
      )

      task = ScheduledTask.find(result[:task_id])
      expect(task.enabled?).to be true
    end

    it "syncs the task to Sidekiq Cron" do
      allow(Sidekiq::Cron::Job).to receive(:create).and_return(true)

      result = Agents::CronConfirmation.confirm_and_persist(
        confirmation_id: "valid_token",
        agent: agent
      )

      expect(Sidekiq::Cron::Job).to have_received(:create).with(
        hash_including(
          cron: "0 9 * * 1",
          class: "TestJob"
        )
      )
    end
  end
end
