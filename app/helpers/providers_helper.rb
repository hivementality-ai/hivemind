# frozen_string_literal: true

module ProvidersHelper
  def provider_badge_bg(provider_type)
    case provider_type
    when "anthropic"
      "bg-orange-600"
    when "openai"
      "bg-green-600"
    when "ollama"
      "bg-purple-600"
    when "openai_compatible"
      "bg-blue-600"
    else
      "bg-gray-600"
    end
  end

  def provider_badge_icon(provider_type)
    case provider_type
    when "anthropic"
      "A"
    when "openai"
      "O"
    when "ollama"
      "OL"
    when "openai_compatible"
      "OC"
    else
      "?"
    end
  end

  def placeholder_for(provider_type)
    case provider_type
    when "anthropic"
      "sk-ant-..."
    when "openai"
      "sk-..."
    when "ollama"
      "Leave blank for local Ollama"
    when "openai_compatible"
      "API key (optional for local servers)"
    else
      "Enter API key..."
    end
  end
end
