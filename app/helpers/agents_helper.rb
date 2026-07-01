# frozen_string_literal: true

module AgentsHelper
  # Renders an agent avatar (image or fallback initial).
  # Sizes: :xs, :sm, :md, :lg, :xl
  AVATAR_SIZES = {
    xs: { dim: "w-6 h-6", text: "text-xs" },
    sm: { dim: "w-8 h-8", text: "text-xs" },
    md: { dim: "w-10 h-10", text: "text-sm" },
    lg: { dim: "w-12 h-12", text: "text-base" },
    xl: { dim: "w-16 h-16", text: "text-xl" }
  }.freeze

  TOOL_CATEGORIES = {
    "Files & Code" => %w[file_read file_write file_edit file_send glob grep pdf_read shell],
    "Web & Network" => %w[web_search web_fetch http_request browser],
    "Communication" => %w[message email gmail google_gmail],
    "Media" => %w[image image_generate tts stt canvas],
    "Integrations" => %w[jira trello google_drive google_calendar cloud_storage gateway],
    "Agent Orchestration" => %w[delegate delegation_status coding_agent coding_agent_status deep_research deep_research_status agents_list],
    "Sessions & Memory" => %w[sessions_list sessions_send sessions_history session_status memory_search memory_store memory_update memory_stats],
    "System" => %w[cron cron_script heartbeat_write ask_user plan_mode create_skill create_tool]
  }.freeze

  # Returns tools grouped by category. Custom (non-builtin) tools get their own group.
  # Any builtin tool not listed in TOOL_CATEGORIES falls into "Other".
  def grouped_tools(tools)
    builtin, custom = tools.partition(&:builtin?)

    groups = {}

    # Map builtin tools to categories
    executor_to_category = {}
    TOOL_CATEGORIES.each do |cat, types|
      types.each { |t| executor_to_category[t] = cat }
    end

    TOOL_CATEGORIES.each_key do |cat|
      matching = builtin.select { |t| executor_to_category[t.executor_type] == cat }
      groups[cat] = matching.sort_by(&:name) if matching.any?
    end

    # Catch any uncategorized builtins
    categorized_types = TOOL_CATEGORIES.values.flatten
    other = builtin.reject { |t| categorized_types.include?(t.executor_type) }
    groups["Other"] = other.sort_by(&:name) if other.any?

    # Custom tools in their own group
    groups["Custom Tools"] = custom.sort_by(&:name) if custom.any?

    groups
  end

  def agent_avatar(agent, size: :md)
    s = AVATAR_SIZES[size] || AVATAR_SIZES[:md]

    if agent.avatar.attached?
      image_tag rails_blob_path(agent.avatar, only_path: true),
        class: "#{s[:dim]} rounded-lg object-cover flex-shrink-0",
        alt: agent.name
    else
      content_tag(:div,
        agent.name[0].upcase,
        class: "#{s[:dim]} bg-brand rounded-lg flex items-center justify-center text-white font-bold #{s[:text]} flex-shrink-0"
      )
    end
  end
end
