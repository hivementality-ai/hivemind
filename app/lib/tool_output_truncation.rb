# frozen_string_literal: true

# Caps tool output at a byte limit for exports.
module ToolOutputTruncation
  MAX_TOOL_OUTPUT_SIZE = 10_240 # 10KB

  private

  def truncate_output(output)
    return nil unless output
    return output if output.bytesize <= MAX_TOOL_OUTPUT_SIZE

    output.byteslice(0, MAX_TOOL_OUTPUT_SIZE) + "\n... [truncated at #{MAX_TOOL_OUTPUT_SIZE} bytes]"
  end
end
