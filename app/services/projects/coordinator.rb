# frozen_string_literal: true

module Projects
  class Coordinator
    def self.call
      new.call
    end

    def call
      Project.active_or_blocked.find_each do |project|
        coordinate(project)
      rescue StandardError => e
        Rails.logger.error("[Projects::Coordinator] Error on project #{project.id}: #{e.message}")
      end
    end

    private

    def coordinate(project)
      check_pending_approvals(project)
      check_stalled_milestones(project)
      start_unblocked_milestones(project)
      update_project_status(project)
      check_deadline(project)
      send_digests(project)
    end

    def check_pending_approvals(project)
      Projects::ApprovalReminder.call(project: project)
    end

    def check_stalled_milestones(project)
      Projects::StallDetector.call(project: project)
    end

    def start_unblocked_milestones(project)
      project.milestones.where(status: "pending").ordered.each do |milestone|
        next unless milestone.ready_to_start?
        next if project.milestones.where(status: "in_progress").any?

        Projects::MilestoneRunner.call(milestone: milestone)
      end
    end

    def update_project_status(project)
      if project.milestones.awaiting_review.any?
        project.update!(status: "blocked") unless project.status == "blocked"
      elsif project.milestones.where.not(status: %w[completed skipped]).none?
        project.update!(status: "completed", completed_at: Time.current)
        Projects::EventLogger.call(project: project, event_type: "project_completed",
          summary: "All milestones completed!")
      elsif project.status == "blocked"
        project.update!(status: "active")
      end
    end

    def check_deadline(project)
      Projects::DeadlineChecker.call(project: project)
    end

    def send_digests(project)
      Projects::DigestBuilder.call(project: project)
    end
  end
end
