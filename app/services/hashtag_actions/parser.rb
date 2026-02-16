# frozen_string_literal: true

module HashtagActions
  class Parser
    # Parses hashtag actions from user messages.
    # Returns a ParseResult with extracted actions and the cleaned message.
    #
    # Supported formats:
    #   #remember This is important
    #   #todo Fix the login bug
    #   #schedule 2h Check on deployment
    #   #remember #todo Buy groceries     (composable — both fire)
    #   Just chatting #remember save this  (inline — action extracted, rest sent to LLM)

    ParseResult = Struct.new(:actions, :clean_message, :bypass_llm?, keyword_init: true)
    Action = Struct.new(:name, :payload, :raw, keyword_init: true)

    # Hashtags that fully bypass the LLM (response is handled by the action itself)
    BYPASS_ACTIONS = %w[remember forget search status reset help approve deny].freeze

    # Hashtags that augment the LLM call (modify behavior but still chat)
    AUGMENT_ACTIONS = %w[mood voice image summarize].freeze

    # Hashtags that trigger side effects + still chat
    SIDEEFFECT_ACTIONS = %w[todo schedule handoff delegate private].freeze

    ALL_ACTIONS = (BYPASS_ACTIONS + AUGMENT_ACTIONS + SIDEEFFECT_ACTIONS).freeze

    HASHTAG_PATTERN = /#(#{ALL_ACTIONS.join("|")})\b/i

    def self.call(message:)
      new(message:).call
    end

    def initialize(message:)
      @message = message.to_s.strip
    end

    def call
      return no_actions if @message.blank?

      actions = extract_actions
      return no_actions if actions.empty?

      clean = clean_message(actions)
      bypass = actions.all? { |a| BYPASS_ACTIONS.include?(a.name) } && clean.blank?

      ParseResult.new(
        actions: actions,
        clean_message: clean,
        bypass_llm?: bypass
      )
    end

    private

    def extract_actions
      actions = []
      remaining = @message.dup

      # Scan for all hashtag actions in order
      @message.scan(HASHTAG_PATTERN) do |match|
        action_name = match[0].downcase
        next if actions.any? { |a| a.name == action_name } # Skip dupes

        # Extract payload: text after this hashtag until the next hashtag or end
        pattern = /##{action_name}\s*/i
        if remaining =~ pattern
          after = $~.post_match
          # Payload is everything until next #action or end of string
          payload = if after =~ HASHTAG_PATTERN
                      after[0...$~.begin(0)].strip
          else
                      after.strip
          end

          actions << Action.new(
            name: action_name,
            payload: payload.presence,
            raw: "#{$~}#{payload}"
          )
        end
      end

      actions
    end

    def clean_message(actions)
      clean = @message.dup
      actions.each do |action|
        # Remove the hashtag and its payload from the message
        clean = clean.sub(/##{action.name}\s*/i, "")
        clean = clean.sub(action.payload, "") if action.payload.present?
      end
      clean.strip.squeeze(" ")
    end

    def no_actions
      ParseResult.new(actions: [], clean_message: @message, bypass_llm?: false)
    end
  end
end
