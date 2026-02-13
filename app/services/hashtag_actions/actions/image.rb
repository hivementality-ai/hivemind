# frozen_string_literal: true

module HashtagActions
  module Actions
    class Image < Base
      def execute
        prompt = payload.presence || clean_message

        return { response: "Generate what? Use: #image <description>", status: "no_payload" } if prompt.blank?

        # Use the image tool executor if available
        tool = Tool.find_by(identifier: "image")
        unless tool
          return { response: "Image generation tool is not available.", status: "no_tool" }
        end

        result = Tools::Executor.call(
          tool: tool,
          agent: agent,
          session: session,
          parameters: { "action" => "generate", "prompt" => prompt }
        )

        if result.success?
          { response: result.data[:output].to_s, bypass: false, status: "generated" }
        else
          { response: "Image generation failed: #{result.error}", status: "error" }
        end
      rescue StandardError => e
        { response: "Image generation error: #{e.message}", status: "error" }
      end
    end
  end
end
