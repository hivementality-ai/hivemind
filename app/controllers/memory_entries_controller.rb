# frozen_string_literal: true

class MemoryEntriesController < ApplicationController
  before_action :set_agent
  before_action :set_memory_entry, only: [ :destroy ]
  before_action :authorize_admin_or_owner!, only: [ :destroy ]

  def index
    @memories = if params[:q].present?
      result = Memory::Search.call(agent: @agent, query: params[:q], limit: 50)
      result.success? ? result.data[:results].map { |r| MemoryEntry.find(r[:id]) } : []
    else
      @agent.memory_entries.order(created_at: :desc)
    end
    @total_count = @agent.memory_entries.count
  end

  def destroy
    @memory_entry.destroy
    redirect_to agent_memory_entries_path(@agent), notice: "Memory deleted."
  end

  private

  def set_agent
    @agent = Agent.find_by_slug(params[:agent_slug])
    render file: "public/404.html", status: :not_found unless @agent
  end

  def set_memory_entry
    @memory_entry = @agent.memory_entries.find(params[:id])
  end
end
