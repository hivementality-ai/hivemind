# frozen_string_literal: true

# Async job to sync agent memories to workspace filesystem.
# Triggered on new chat start so the MEMORY.md is fresh when
# the Agent SDK reads it. Uses Haiku for summarization.
class MemoryFileSyncJob < ApplicationJob
  queue_as :low

  def perform(agent_id, query: nil)
    agent = Agent.find_by(id: agent_id)
    return unless agent

    Memory::FileSync.call(agent: agent, query: query)
  end
end
