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
