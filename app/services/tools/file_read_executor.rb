# frozen_string_literal: true

module Tools
  class FileReadExecutor < BaseExecutor
    MAX_SIZE = 100_000
    WORKSPACE_ROOT = "/workspace"

    def call
      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      full_path = path.start_with?("/") ? path : File.join(WORKSPACE_ROOT, path)

      unless WorkspaceIo.file_exists?(full_path)
        return ServiceResponse.failure(error: "File not found: #{path}")
      end

      raw = WorkspaceIo.read_file(full_path, max_bytes: MAX_SIZE)

      content = raw.force_encoding("UTF-8")
      unless content.valid_encoding?
        content = raw.encode("UTF-8", "ASCII-8BIT", invalid: :replace, undef: :replace, replace: "")
                     .gsub(/[^[:print:]\s]/, "")
        if content.strip.length < 50
          return ServiceResponse.failure(error: "File appears to be binary (#{File.extname(full_path)}). Try the .extracted.txt version if available, or use a different tool to process this file type.")
        end
      end

      output = load_related? ? render_with_related(full_path, content) : content
      ServiceResponse.success(data: { output: output, exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Read failed: #{e.message}")
    end

    private

    def load_related?
      val = input["load_related"] || input[:load_related]
      %w[1 true on yes].include?(val.to_s.downcase)
    end

    # When load_related=true, use Agents::ContextBudget to pull in
    # Rails-convention-related files (specs, factories, controllers) up
    # to a 4k-token budget. Primary content stays at the top; related
    # files come labeled with their mode (full or signatures-only).
    def render_with_related(primary_path, primary_content)
      budget = Agents::ContextBudget.new
      results = budget.load_for(primary_path)
      return primary_content if results.size <= 1

      sections = [ "=== #{primary_path} (primary) ===", primary_content ]
      results.drop(1).each do |entry|
        sections << "=== #{entry[:file]} (#{entry[:mode]}) ===" << entry[:content].to_s
      end
      sections << "\n[Loaded #{results.size} files, #{budget.tokens_used} tokens used of #{budget.stats[:budget]} budget]"
      sections.join("\n")
    end
  end
end
