# frozen_string_literal: true

module Approvals
  # What a person sees and may change on an approval card for a held tool call:
  # a plain-words title and the exact fields, per ask-first category.
  class CardFields
    Field = Struct.new(:key, :label, :value, :long, keyword_init: true)

    SPECS = {
      "send_email" => {
        verb: "send an email",
        fields: [ %w[to To], %w[cc Cc], %w[bcc Bcc], %w[subject Subject], %w[body Message long] ]
      },
      "post_message" => {
        verb: "post a message",
        fields: [ %w[channel Channel], %w[to To], %w[message Message long] ]
      },
      "delete_file" => {
        verb: "delete a file",
        fields: [ %w[remote Storage], %w[path File] ]
      },
      "external_write" => {
        verb: "change something on another website or service",
        fields: [ %w[method Method], %w[url Address], %w[path Address], %w[body Contents long] ]
      }
    }.freeze

    # @param approval [ApprovalRequest] a "tool_call" request
    def initialize(approval)
      @approval = approval
      @params = approval.params || {}
    end

    # @return [String] e.g. "send an email"
    def verb
      spec[:verb]
    end

    # @return [String] e.g. "Sam wants to send an email"
    def headline
      "#{@approval.agent.name} wants to #{verb}"
    end

    # @return [Array<Field>] the fields that have a value, with the value as text
    def fields
      arguments = @params["arguments"] || {}
      spec[:fields].filter_map do |key, label, long|
        next if arguments[key].blank?

        Field.new(key:, label:, value: display(arguments[key]), long: long == "long")
      end
    end

    # Applies a person's edits to the stored arguments. Only fields shown on the card can change.
    # A field that held structured data must come back as valid JSON.
    #
    # @param edits [Hash{String => String}] field key => new text
    # @return [Hash, nil] the new arguments, or nil when an edit is not acceptable
    def edited_arguments(edits)
      arguments = (@params["arguments"] || {}).dup
      allowed = spec[:fields].map(&:first)

      edits.to_h.each do |key, text|
        next unless allowed.include?(key.to_s)

        arguments[key.to_s] = coerce(arguments[key.to_s], text.to_s)
        return nil if arguments[key.to_s] == :invalid
      end
      arguments
    end

    private

    def spec
      SPECS.fetch(@params["category"]) { SPECS["external_write"] }
    end

    def display(value)
      value.is_a?(String) ? value : JSON.pretty_generate(value)
    end

    def coerce(original, text)
      return text unless original.is_a?(Hash) || original.is_a?(Array)

      JSON.parse(text)
    rescue JSON::ParserError
      :invalid
    end
  end
end
