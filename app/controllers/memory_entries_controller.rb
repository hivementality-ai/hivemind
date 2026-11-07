# frozen_string_literal: true

# The "What <agent> remembers about you" page: distilled memories only, with
# edit, forget (undoable), pin and a confirmed bulk forget by topic.
class MemoryEntriesController < ApplicationController
  before_action :set_agent, except: [ :landing ]
  before_action :set_memory_entry, only: [ :update, :destroy, :restore, :pin ]
  before_action :authorize_admin_or_owner!, except: [ :index, :landing ]

  # Sidebar entry: straight to the only agent's page, else the agent list to pick one.
  def landing
    agents = Agent.visible.enabled.order(:id).limit(2).to_a
    if agents.one?
      redirect_to agent_memory_entries_path(agents.first)
    else
      redirect_to agents_path, notice: "Pick an agent to see what it remembers about you."
    end
  end

  def index
    @query = params[:q].to_s.strip
    entries = visible_entries
    entries = entries.where(id: matching_ids(entries)) if @query.present?
    @total_count = visible_entries.count
    @grouped = entries.order(pinned: :desc, created_at: :desc).group_by(&:kind)
    @forgotten = @agent.memory_entries.durable.forgotten.order(updated_at: :desc).limit(20)
  end

  def update
    content = params.dig(:memory_entry, :content).to_s.strip
    return redirect_to(page_path, alert: "A memory can't be empty.") if content.blank?

    if content != @memory_entry.content
      @memory_entry.update!(content: content, embedding: nil, shadow_embedding: nil)
      MemoryEmbeddingJob.perform_later(@memory_entry.id)
    end
    redirect_to page_path, notice: "Saved."
  end

  # Forgets an active memory (undoable); removes one already forgotten for good.
  def destroy
    if @memory_entry.status == "archived" && @memory_entry.metadata.key?("forgotten_at")
      @memory_entry.destroy!
      redirect_to page_path, notice: "Removed for good."
    else
      @memory_entry.forget!
      redirect_to page_path, notice: "Forgotten. You can undo this under Recently forgotten."
    end
  end

  def restore
    @memory_entry.restore!
    redirect_to page_path, notice: "Restored."
  end

  def pin
    @memory_entry.update!(pinned: params[:pinned].to_s == "true")
    redirect_to page_path
  end

  # Shows exactly which memories "forget everything about <topic>" would delete.
  def confirm_forget
    @topic = params[:topic].to_s.strip
    return redirect_to(page_path, alert: "Type a topic to forget.") if @topic.blank?

    matches = topic_matches(@topic)
    @doomed = matches.where(pinned: false).order(created_at: :desc)
    @pinned_count = matches.where(pinned: true).count
  end

  def bulk_forget
    topic = params[:topic].to_s.strip
    return redirect_to(page_path, alert: "Type a topic to forget.") if topic.blank?

    ids = Array(params[:ids]).map(&:to_i)
    count = topic_matches(topic).where(pinned: false, id: ids).destroy_all.size
    redirect_to page_path, notice: "Forgot #{count} #{'memory'.pluralize(count)} about #{topic}."
  end

  private

  def set_agent
    @agent = Agent.find_by_slug(params[:agent_slug])
    render file: "public/404.html", status: :not_found unless @agent
  end

  def set_memory_entry
    @memory_entry = @agent.memory_entries.durable.find(params[:id])
  end

  def page_path
    agent_memory_entries_path(@agent)
  end

  def visible_entries
    @agent.memory_entries.durable.active
  end

  def topic_matches(topic)
    visible_entries.where("content ILIKE ?", "%#{MemoryEntry.sanitize_sql_like(topic)}%")
  end

  def matching_ids(entries)
    result = Memory::Search.call(agent: @agent, query: @query, limit: 50)
    return [] unless result.success?

    result.data[:results].map { |r| r[:id] } & entries.pluck(:id)
  end
end
