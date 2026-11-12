# frozen_string_literal: true

require "digest"

module TeamChats
  # A bounded unit of team work rooted in a real user message. The ledger is
  # persisted so nested tool calls, SDK callbacks and job retries share limits.
  class Turn
    MAX_HANDOFFS = 6
    MAX_REQUESTS_PER_TARGET = 2
    MAX_DEPTH = 3
    STATE_KEY = "team_turn"
    CONTEXT_KEY = "team_chat_execution"

    def initialize(message)
      @message = message
    end

    def start!
      @message.with_lock do
        return false if @message.metadata&.key?(STATE_KEY)

        write_state("status" => "running", "handoffs" => [])
      end
      true
    end

    def running?
      state["status"] == "running"
    end

    def finish!(status = "finished")
      @message.with_lock do
        current = @message.metadata&.dig(STATE_KEY)
        write_state(current.merge("status" => status)) if current&.dig("status") == "running"
      end
    end

    def self.stop_active!(session)
      session.team_chat_messages.where(sender_type: "user")
        .where("metadata -> ? ->> 'status' = ?", STATE_KEY, "running").find_each do |message|
        new(message).finish!("stopped")
      end
    end

    def reserve!(from:, target:, task:)
      @message.with_lock do
        current = @message.metadata&.dig(STATE_KEY) || {}
        return ServiceResponse.failure(error: "This team turn has stopped. Return the current results to the user.") unless current["status"] == "running"

        handoffs = current.fetch("handoffs", [])
        fingerprint = Digest::SHA256.hexdigest([ from.id, target.id, task.strip.gsub(/\s+/, " ") ].join("\n"))
        duplicate = handoffs.find { |entry| entry["fingerprint"] == fingerprint }
        if duplicate
          return ServiceResponse.failure(error: "This handoff was already requested (#{duplicate['status']}). Use its existing result; do not ask again. #{duplicate['result']}")
        end
        if handoffs.size >= MAX_HANDOFFS
          return ServiceResponse.failure(error: "The shared limit of #{MAX_HANDOFFS} handoffs has been reached. Synthesize the available results and report any unfinished work.")
        end
        if handoffs.count { |entry| entry["to"] == target.id } >= MAX_REQUESTS_PER_TARGET
          return ServiceResponse.failure(error: "#{target.name} has already received #{MAX_REQUESTS_PER_TARGET} assignments this turn. Resolve the remaining issue or ask the user for a decision.")
        end

        entry = { "id" => SecureRandom.uuid, "from" => from.id, "to" => target.id,
                  "fingerprint" => fingerprint, "task" => task.truncate(2000), "status" => "running" }
        write_state(current.merge("handoffs" => handoffs + [ entry ]))
        ServiceResponse.success(data: { handoff_id: entry["id"] })
      end
    end

    def record_result!(handoff_id, status:, result:)
      @message.with_lock do
        current = @message.metadata.fetch(STATE_KEY)
        entry = current.fetch("handoffs").find { |item| item["id"] == handoff_id }
        return unless entry

        entry.merge!("status" => status, "result" => result.to_s.truncate(3000))
        write_state(current)
      end
    end

    def with_agent_context(session, depth:, active_agent_ids:)
      context = { "turn_message_id" => @message.id, "depth" => depth, "active_agent_ids" => active_agent_ids }
      session.with_lock { session.update!(metadata: (session.metadata || {}).merge(CONTEXT_KEY => context)) }
      yield
    ensure
      session.with_lock do
        if session.metadata&.dig(CONTEXT_KEY) == context
          session.update!(metadata: session.metadata.except(CONTEXT_KEY))
        end
      end
    end

    def prompt
      current = state
      handoffs = current.fetch("handoffs", [])
      lines = [
        "## Shared team task",
        "Original user request (the goal for this turn):",
        @message.content,
        "",
        "Keep the requested deliverable and definition of done in view. If either is unclear, state a reasonable scope or ask for the specific missing decision.",
        "Each handoff must add evidence, a result, a decision, or a concrete blocker. Include the bounded task, source/artifact links, expected output, and return owner.",
        "Return results to the requester. Do not send acknowledgment-only messages, poll repeatedly, or delegate back to an agent waiting on you.",
        "At most #{MAX_HANDOFFS} handoffs total and #{MAX_REQUESTS_PER_TARGET} assignments per teammate are allowed this turn. #{handoffs.size} handoffs used.",
        "After a focused review and repair, synthesize or report the unresolved decision. Stop when done; a handoff limit does not mean the goal was achieved."
      ]
      handoffs.each do |entry|
        lines << "Handoff #{entry['id']} (agent #{entry['from']} to agent #{entry['to']}): #{entry['status']}. #{entry['task']}"
        lines << "Result: #{entry['result']}" if entry["result"].present?
      end
      lines.join("\n")
    end

    def message_id
      @message.id
    end

    private

    def state
      @message.reload.metadata&.dig(STATE_KEY) || {}
    end

    def write_state(value)
      @message.update!(metadata: (@message.metadata || {}).merge(STATE_KEY => value))
    end
  end
end
