# frozen_string_literal: true

module HashtagActions
  class Registry
    # Maps hashtag names to their executor classes.
    # Each executor responds to .call(action:, agent:, session:, context:)

    ACTIONS = {
      "plan"      => "HashtagActions::Actions::Plan",
      "exit"      => "HashtagActions::Actions::ExitPlan",
      "remember"  => "HashtagActions::Actions::Remember",
      "forget"    => "HashtagActions::Actions::Forget",
      "search"    => "HashtagActions::Actions::Search",
      "todo"      => "HashtagActions::Actions::Todo",
      "schedule"  => "HashtagActions::Actions::Schedule",
      "summarize" => "HashtagActions::Actions::Summarize",
      "status"    => "HashtagActions::Actions::Status",
      "reset"     => "HashtagActions::Actions::Reset",
      "compact"   => "HashtagActions::Actions::Compact",
      "help"      => "HashtagActions::Actions::Help",
      "mood"      => "HashtagActions::Actions::Mood",
      "voice"     => "HashtagActions::Actions::Voice",
      "image"     => "HashtagActions::Actions::Image",
      "handoff"   => "HashtagActions::Actions::Handoff",
      "delegate"  => "HashtagActions::Actions::Delegate",
      "private"   => "HashtagActions::Actions::Private",
      "approve"   => "HashtagActions::Actions::Approve",
      "deny"      => "HashtagActions::Actions::Deny"
    }.freeze

    def self.executor_for(action_name)
      klass = ACTIONS[action_name.downcase]
      return nil unless klass

      klass.constantize
    rescue NameError => e
      Rails.logger.warn("[HashtagActions] Executor not found: #{klass} — #{e.message}")
      nil
    end

    def self.registered?(action_name)
      ACTIONS.key?(action_name.downcase)
    end

    def self.all_actions
      ACTIONS.keys
    end
  end
end
