# frozen_string_literal: true

class SessionsController < ApplicationController
  include SessionChatActions

  before_action :authenticate_user!
  before_action :set_agent, only: [ :create ]
  before_action :set_session, only: [ :show, :message, :interrupt, :update, :canvas, :export, :timeline ]

  # GET /sessions — list all sessions
  def index
    # If agent_id is passed via GET, auto-create a session and redirect to chat
    if params[:agent_id].present? && request.get?
      agent = resolve_agent(params[:agent_id])
      if agent
        session = create_chat_session(agent: agent, user: current_user)
        redirect_to session_path(session) and return
      end
    end

    @agents = Agent.enabled.order(:name)

    sessions_scope = Session.includes(:agent)
                            .where(status: :active)
                            .order(Arel.sql("COALESCE(last_activity_at, created_at) DESC"))

    # Filter by agent
    if params[:filter_agent].present?
      sessions_scope = sessions_scope.where(agent_id: params[:filter_agent])
    end

    # Filter by session type
    case params[:filter_type]
    when "delegated"
      sessions_scope = sessions_scope.where.not(team_chat_session_id: nil)
    when "direct"
      sessions_scope = sessions_scope.where(team_chat_session_id: nil)
    end

    @sessions = sessions_scope.limit(100)

    # One most-recent session per agent, sorted by recency (for compact cards section)
    @recent_agent_sessions = @agents.map do |agent|
      recent = Session.where(agent: agent)
                      .active_sessions
                      .order(Arel.sql("COALESCE(last_activity_at, created_at) DESC"))
                      .first
      { agent: agent, session: recent }
    end.sort_by do |entry|
      s = entry[:session]
      s ? -(s.last_activity_at || s.created_at).to_i : 1
    end
  end

  # POST /sessions — start a new chat with an agent
  def create
    @session = create_chat_session(agent: @agent, user: current_user)

    redirect_to session_path(@session)
  end

  # GET /sessions/:id — show chat interface
  def show
    @agent = @session.agent
    @messages = @session.transcript || []
    @attachments = @session.chat_attachments.includes(file_attachment: :blob).index_by(&:message_index)
    @processing = Redis.current.get("session_processing:#{@session.id}") == "1"

    # Recent sessions for this agent (sidebar)
    @recent_sessions = Session.where(agent: @agent)
                              .active_sessions
                              .where.not(id: @session.id)
                              .order(Arel.sql("COALESCE(last_activity_at, created_at) DESC"))
                              .limit(15)
  end

  # POST /sessions/:id/message — send a message (async via Sidekiq + ActionCable)
  def message
    result = process_chat_message(
      session: @session,
      message: params[:message],
      images: params[:images],
      files: params[:files]
    )

    if result == :blank
      head :unprocessable_entity
    else
      head :ok
    end
  end

  # PATCH /sessions/:id — rename a chat session
  def update
    result = rename_chat_session(session: @session, title: params[:title])

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: { title: result[:title] }
    end
  end

  # GET /sessions/:id/canvas — live canvas view
  def canvas
    @agent = @session.agent
  end

  # GET /sessions/:id/timeline — interleaved timeline of all session activity
  def timeline
    @agent = @session.agent

    messages = (@session.transcript || []).map.with_index do |msg, idx|
      { kind: :message, ts: Time.parse(msg["timestamp"].to_s), data: msg, idx: idx }
    rescue ArgumentError
      { kind: :message, ts: @session.created_at, data: msg, idx: idx }
    end

    tool_entries = @session.tool_executions.includes(:tool).map do |te|
      { kind: :tool, ts: te.created_at, data: te }
    end

    usage_entries = @session.usage_records.map do |ur|
      { kind: :usage, ts: ur.created_at, data: ur }
    end

    @entries = (messages + tool_entries + usage_entries).sort_by { |e| e[:ts] }

    totals = @session.usage_records
    @total_input_tokens  = totals.sum(:input_tokens)
    @total_output_tokens = totals.sum(:output_tokens)
    @total_cost_cents    = totals.sum(:cost_cents)
    @tool_count          = @session.tool_executions.count
  end

  # GET /sessions/:id/export — download debug export as JSON
  def export
    result = Sessions::Export.call(session: @session)

    if result.success?
      filename = "session_#{@session.id}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      send_data result.data[:export].to_json, filename: filename, type: "application/json", disposition: "attachment"
    else
      redirect_to session_path(@session), alert: result.error
    end
  end

  # POST /sessions/:id/interrupt — cancel, redirect, or inject into active agent
  def interrupt
    result = send_session_interrupt(session: @session, type: params[:type], message: params[:message])

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: { status: "signal_sent", type: result[:type] }
    end
  end

  private

  def set_agent
    @agent = resolve_agent(params[:agent_id])
    render file: "public/404.html", status: :not_found unless @agent
  end

  def set_session
    @session = Session.find(params[:id])
  end
end
