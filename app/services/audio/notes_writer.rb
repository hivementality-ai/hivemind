# frozen_string_literal: true

module Audio
  # Turns a transcript into short notes with the agent's own model provider.
  class NotesWriter
    Failure = Class.new(StandardError)
    MAX_TRANSCRIPT_CHARS = 120_000
    PROMPT = <<~TEXT
      You turn a transcript of a recording into clean notes. Reply in Markdown with exactly these sections:
      ## Summary
      Two to four sentences.
      ## Decisions
      Bullets. Write "None mentioned." if there were none.
      ## Action items
      Bullets. Name the owner when the speakers named one, like "Dana: send the quote". Write "None mentioned." if there were none.
      ## Open questions
      Bullets. Write "None mentioned." if there were none.
      Use only what the transcript says. Do not invent names, dates or decisions.
    TEXT

    # @param agent [Agent]
    def initialize(agent)
      @agent = agent
    end

    # @param transcript [String]
    # @return [String] Markdown notes
    # @raise [Failure] with a plain-words reason
    def call(transcript)
      resolved = Providers::Resolver.call(provider_name: @agent.model_provider, agent: @agent)
      raise Failure, "No model is available to write the notes." unless resolved.success?

      result = resolved.data[:adapter].chat(
        messages: [ { role: "system", content: PROMPT },
                    { role: "user", content: transcript.to_s.truncate(MAX_TRANSCRIPT_CHARS, omission: "") } ],
        options: { model: BackgroundModel.for(@agent), max_tokens: 2000 }
      )
      raise Failure, "The model could not write the notes: #{result.error.to_s.truncate(100)}" unless result.success?

      result.data[:content].to_s.strip.presence || raise(Failure, "The model sent back empty notes.")
    end
  end
end
