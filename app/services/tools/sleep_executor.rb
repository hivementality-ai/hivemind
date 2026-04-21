# frozen_string_literal: true

module Tools
  class SleepExecutor < BaseExecutor
    MAX_SECONDS = 180 # 3 minutes
    MIN_SECONDS = 1
    POLL_INTERVAL = 1 # check for interrupts every second

    def call
      seconds = parse_seconds
      return ServiceResponse.failure(error: "seconds must be between #{MIN_SECONDS} and #{MAX_SECONDS}") unless seconds.between?(MIN_SECONDS, MAX_SECONDS)

      reason = input["reason"].to_s.strip
      session = config[:session]

      # Broadcast that the agent is sleeping
      if session
        channel = "session_#{session.id}"
        ActionCable.server.broadcast(channel, {
          type: "agent_sleeping",
          seconds: seconds,
          reason: reason.presence,
          timestamp: Time.current.iso8601
        })
      end

      # Sleep in small increments so we can check for cancel/redirect signals
      elapsed = 0
      while elapsed < seconds
        remaining = seconds - elapsed
        nap = [POLL_INTERVAL, remaining].min
        Kernel.sleep(nap)
        elapsed += nap

        # Check for session signals (cancel, redirect) so the agent can be interrupted mid-sleep
        if session
          signal = SessionSignal.check(session.id)
          if signal
            case signal[:type]
            when "cancel"
              raise AgentInterrupted
            when "redirect"
              raise AgentRedirected.new(signal[:message])
            end
          end
        end
      end

      output = "Waited #{seconds} second#{'s' unless seconds == 1}"
      output += " (#{reason})" if reason.present?

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    private

    def parse_seconds
      raw = input["seconds"]
      Integer(raw)
    rescue ArgumentError, TypeError
      0
    end
  end
end
