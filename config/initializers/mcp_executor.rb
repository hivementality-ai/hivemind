# frozen_string_literal: true

Rails.application.config.after_initialize do
  if Tools::Executor.respond_to?(:register)
    Tools::Executor.register("mcp", Tools::McpExecutor)
  end
end
