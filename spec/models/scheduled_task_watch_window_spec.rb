# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledTask, "watch window" do
  def at(hour) = Time.zone.local(2026, 11, 8, hour, 30)

  describe "#quiet_now?" do
    it "is false without a window" do
      expect(build(:scheduled_task).quiet_now?(at(23))).to be(false)
    end

    it "covers a same-day window, end exclusive" do
      task = build(:scheduled_task, quiet_start_hour: 12, quiet_end_hour: 14)
      expect([ 11, 12, 13, 14 ].map { |h| task.quiet_now?(at(h)) }).to eq([ false, true, true, false ])
    end

    it "covers a window that wraps past midnight" do
      task = build(:scheduled_task, quiet_start_hour: 22, quiet_end_hour: 7)
      expect([ 21, 22, 23, 0, 6, 7, 12 ].map { |h| task.quiet_now?(at(h)) })
        .to eq([ false, true, true, true, true, false, false ])
    end
  end

  describe "validations" do
    it "needs both ends of the quiet window" do
      expect(build(:scheduled_task, quiet_start_hour: 22)).not_to be_valid
    end

    it "rejects hours outside 0 to 23 and an empty window" do
      expect(build(:scheduled_task, quiet_start_hour: 24, quiet_end_hour: 7)).not_to be_valid
      expect(build(:scheduled_task, quiet_start_hour: 7, quiet_end_hour: 7)).not_to be_valid
      expect(build(:scheduled_task, digest_hour: 24)).not_to be_valid
    end
  end

  describe "#hold" do
    it "merges by id, keeps the cap and counts what was dropped" do
      task = build(:scheduled_task)
      task.hold([ { id: "a", title: "A" }, { id: "b", title: "B" } ], extra: 0)
      task.hold([ { id: "b", title: "B" } ] + (1..10).map { |i| { id: "n#{i}", title: "N#{i}" } }, extra: 2)

      expect(task.held_items.size).to eq(ScheduledTasks::Precheck::MAX_ITEMS)
      expect(task.held_items.map { |i| i["id"] }.first(3)).to eq(%w[a b n1])
      expect(task.held_changes["extra"]).to eq(2 + 2)
    end
  end
end
