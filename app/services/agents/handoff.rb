# frozen_string_literal: true

module Agents
  # Transfer conversation from one agent to another
  class Handoff
    def self.call(from_agent:, to_agent:, session:, context_summary: nil)
      new(
        from_agent: from_agent,
        to_agent: to_agent,
        session: session,
        context_summary: context_summary
      ).call
    end
    
    def initialize(from_agent:, to_agent:, session:, context_summary: nil)
      @from_agent = from_agent
      @to_agent = to_agent
      @session = session
      @context_summary = context_summary
    end
    
    def call
      ActiveRecord::Base.transaction do
        # Mark original session as handed off
        @session.update!(
          status: "handed_off",
          metadata: @session.metadata.merge(
            handed_off_to: @to_agent.id,
            handed_off_at: Time.current.iso8601
          )
        )
        
        # Create new session for target agent with context
        new_session = create_target_session
        
        # Create team message documenting handoff
        create_team_message(new_session)
        
        # Broadcast to Mission Control
        broadcast_handoff(new_session)
        
        # Audit log
        Audit::Log.call(
          actor: @from_agent.name,
          action: "conversation.handoff",
          resource: @session,
          metadata: {
            from_agent_id: @from_agent.id,
            to_agent_id: @to_agent.id,
            new_session_id: new_session.id,
            context_summary: @context_summary
          }
        )
        
        ServiceResponse.success(
          data: {
            original_session: @session,
            new_session: new_session,
            to_agent: @to_agent
          }
        )
      end
    rescue => e
      ServiceResponse.failure(error: "Handoff failed: #{e.message}")
    end
    
    private
    
    def create_target_session
      # Build context message for new session
      context_message = build_context_message
      
      # Create new session
      Session.create!(
        agent: @to_agent,
        key: generate_session_key,
        status: "active",
        transcript: [context_message],
        metadata: {
          handed_off_from: @from_agent.id,
          original_session_id: @session.id,
          handoff_at: Time.current.iso8601
        }
      )
    end
    
    def build_context_message
      summary = @context_summary || extract_conversation_summary
      
      {
        role: "system",
        content: <<~CONTEXT,
          🔄 This conversation has been handed off from #{@from_agent.name} (#{@from_agent.role}).
          
          ## Context Summary
          #{summary}
          
          ## Instructions
          Continue this conversation as #{@to_agent.role}. The user is expecting your expertise.
          You have access to the full conversation history if needed.
        CONTEXT
        timestamp: Time.current.iso8601
      }
    end
    
    def extract_conversation_summary
      # Extract last few messages as context
      return "No prior context" unless @session.transcript.is_a?(Array)
      
      recent_messages = @session.transcript.last(5)
      
      messages = recent_messages.map do |msg|
        next unless msg.is_a?(Hash)
        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        "#{role}: #{content&.first(100)}"
      end.compact
      
      messages.join("\n")
    end
    
    def create_team_message(new_session)
      return unless @from_agent.team_id && @to_agent.team_id == @from_agent.team_id
      
      TeamMessage.create!(
        team_id: @from_agent.team_id,
        agent: @from_agent,
        message_type: "handoff",
        content: "Handed off conversation to #{@to_agent.name}: #{@context_summary || 'conversation transfer'}",
        metadata: {
          from_agent_id: @from_agent.id,
          to_agent_id: @to_agent.id,
          original_session_id: @session.id,
          new_session_id: new_session.id
        }
      )
    end
    
    def broadcast_handoff(new_session)
      ActionCable.server.broadcast(
        "mission_control_channel",
        {
          type: "conversation_handoff",
          from_agent_id: @from_agent.id,
          from_agent_name: @from_agent.name,
          to_agent_id: @to_agent.id,
          to_agent_name: @to_agent.name,
          original_session_id: @session.id,
          new_session_id: new_session.id,
          timestamp: Time.current.iso8601
        }
      )
    end
    
    def generate_session_key
      "session_#{SecureRandom.hex(16)}"
    end
  end
end
