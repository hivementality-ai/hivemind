# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :team
  belongs_to :user
  has_many :milestones, class_name: "ProjectMilestone", dependent: :destroy
  has_many :events, class_name: "ProjectEvent", dependent: :destroy

  validates :title, presence: true
  validates :status, inclusion: { in: %w[planning active paused blocked completed cancelled] }
  validates :priority, inclusion: { in: %w[low normal high urgent] }

  scope :active_or_blocked, -> { where(status: %w[active blocked]) }
  scope :for_team, ->(team) { where(team: team) }

  def workspace_path
    slug = title.parameterize(separator: "_")
    "/workspace/projects/#{slug}_#{id}"
  end

  def ensure_workspace!
    FileUtils.mkdir_p(workspace_path)
    workspace_path
  end

  def project_files
    return [] unless File.directory?(workspace_path)

    Dir.glob(File.join(workspace_path, "**", "*"))
       .select { |f| File.file?(f) }
       .sort_by { |f| File.mtime(f) }
       .reverse
       .map do |path|
      {
        path: path,
        name: File.basename(path),
        relative: path.sub("#{workspace_path}/", ""),
        size: File.size(path),
        modified: File.mtime(path)
      }
    end
  end

  def progress_percentage
    total = milestones.count
    return 0 if total.zero?

    ((milestones.where(status: "completed").count.to_f / total) * 100).round
  end

  def blocked?
    milestones.where(status: "needs_review").any?
  end

  def notification_pref(key, default = nil)
    notification_prefs.dig(key.to_s) || default
  end

  def digest_mode
    notification_pref("digest_mode", "realtime")
  end

  def approval_reminder_hours
    notification_pref("approval_reminder_hours", 4)
  end

  def approval_max_reminders
    notification_pref("approval_max_reminders", 3)
  end

  def approval_escalation_hours
    notification_pref("approval_escalation_hours", 24)
  end
end
