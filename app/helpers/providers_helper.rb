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

  # Plain-language, actionable explanation for an open provider circuit.
  # The point of the banner is that a human knows exactly what to do next.
  def provider_circuit_explanation(circuit)
    case circuit.reason.to_s
    when "quota_exhausted"
      "The account has no usage credit left. Top it up at claude.ai/settings/usage, then hit Retry now."
    when "auth_invalid"
      "The API key or OAuth token is invalid or expired. Replace it, then hit Retry now."
    when "forbidden"
      "This credential is not permitted to use the requested model. Check the account's model access or pick a different model."
    when "local_port_exhaustion"
      "This host has run out of ephemeral network ports. Hivemind stopped dialling so the machine can recover — see MULTI-STACK.md for the sysctl tuning."
    else
      "Repeated permanent failures on this credential. Check the provider settings, then hit Retry now."
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
