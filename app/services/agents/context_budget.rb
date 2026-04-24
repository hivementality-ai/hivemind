# frozen_string_literal: true

module Agents
  # Budget-aware related-file loader. Given a primary file path, loads it
  # fully and fills a token budget with related files (spec first, then
  # factory, then service, etc.). Over-budget related files fall back to
  # signature-only extraction.
  #
  # Ports rubyn-code's context/context_budget.rb, with two adaptations:
  #   - reads files through Tools::WorkspaceIo instead of the local FS
  #     so workspace-container paths work
  #   - discovers related files from Rails conventions on the file path
  #     itself (no codebase index required)
  class ContextBudget
    CHARS_PER_TOKEN = 4
    DEFAULT_BUDGET = 4000 # tokens

    PRIORITY_MAP = {
      "spec" => 1,
      "factory" => 2,
      "service" => 3,
      "model" => 4,
      "controller" => 5,
      "serializer" => 6,
      "concern" => 7,
      "helper" => 8,
      "migration" => 9
    }.freeze

    attr_reader :loaded_files, :signature_files, :tokens_used

    def initialize(budget: DEFAULT_BUDGET)
      @budget = budget
      @loaded_files = []
      @signature_files = []
      @tokens_used = 0
    end

    # @param file_path [String] absolute or workspace-relative path
    # @param related_files [Array<String>] explicit related paths (overrides discovery)
    # @return [Array<Hash>] array of { file:, content:, mode: :full|:signatures }
    def load_for(file_path, related_files: [])
      results = []
      primary_content = safe_read(file_path)
      return results unless primary_content

      primary_tokens = estimate_tokens(primary_content)
      @tokens_used = primary_tokens
      @loaded_files << file_path
      results << { file: file_path, content: primary_content, mode: :full }

      related_files = discover_related_files(file_path) if related_files.empty?
      sorted = prioritize(related_files)
      remaining = @budget - @tokens_used
      remaining = load_full_files(sorted, results, remaining)
      load_signature_files(sorted, results, remaining)

      results
    end

    # Returns a signatures-only projection of `content` — class/module
    # headers, method signatures, attr_accessors, associations, etc.
    # Typically 10–20% of the original size.
    def extract_signatures(content)
      signatures = []
      indent_stack = []

      content.lines.each do |line|
        process_signature_line(line, signatures, indent_stack)
      end

      signatures.join
    end

    def stats
      {
        budget: @budget,
        tokens_used: @tokens_used,
        utilization: @budget.positive? ? (@tokens_used.to_f / @budget).round(3) : 0.0,
        full_files: @loaded_files.size,
        signature_files: @signature_files.size
      }
    end

    private

    # Rails-convention path inference. Given `app/models/user.rb`, yields
    # `spec/models/user_spec.rb`, `spec/factories/users.rb`,
    # `app/controllers/users_controller.rb`, and so on. Returns only
    # paths that actually exist on disk.
    def discover_related_files(file_path)
      return [] unless file_path

      base = File.basename(file_path, File.extname(file_path))
      candidates = []

      if file_path.include?("app/models/")
        singular = base
        plural = ActiveSupport::Inflector.pluralize(singular)
        candidates << file_path.sub("app/models/", "spec/models/").sub(/\.rb\z/, "_spec.rb")
        candidates << file_path.sub("app/models/#{singular}.rb", "spec/factories/#{plural}.rb")
        candidates << file_path.sub("app/models/#{singular}.rb", "app/controllers/#{plural}_controller.rb")
      elsif file_path.include?("app/controllers/")
        candidates << file_path.sub("app/controllers/", "spec/controllers/").sub(/\.rb\z/, "_spec.rb")
        candidates << file_path.sub("app/controllers/", "spec/requests/").sub(/_controller\.rb\z/, "_spec.rb")
      elsif file_path.include?("app/services/")
        candidates << file_path.sub("app/services/", "spec/services/").sub(/\.rb\z/, "_spec.rb")
      elsif file_path.include?("spec/")
        candidates << file_path.sub("spec/", "app/").sub(/_spec\.rb\z/, ".rb")
      end

      candidates.uniq.select { |p| safe_exists?(p) }
    end

    def load_full_files(sorted, results, remaining)
      sorted.each do |rel_path|
        content = safe_read(rel_path)
        next unless content

        size = estimate_tokens(content)
        next unless size <= remaining

        results << { file: rel_path, content: content, mode: :full }
        @loaded_files << rel_path
        @tokens_used += size
        remaining -= size
      end
      remaining
    end

    def load_signature_files(sorted, results, remaining)
      sorted.each do |rel_path|
        next if @loaded_files.include?(rel_path)

        content = safe_read(rel_path)
        next unless content

        sigs = extract_signatures(content)
        sig_size = estimate_tokens(sigs)
        next unless sig_size <= remaining

        results << { file: rel_path, content: sigs, mode: :signatures }
        @signature_files << rel_path
        @tokens_used += sig_size
        remaining -= sig_size
      end
    end

    def process_signature_line(line, signatures, indent_stack)
      stripped = line.strip
      if signature_line?(stripped)
        signatures << line
        indent_stack << current_indent(line) if block_opener?(stripped)
      elsif stripped == "end" && indent_stack.any? && current_indent(line) <= indent_stack.last
        signatures << line
        indent_stack.pop
      elsif class_or_module_line?(stripped)
        signatures << line
        indent_stack << current_indent(line)
      end
    end

    def prioritize(files)
      files.sort_by do |path|
        basename = File.basename(path, ".*").downcase
        PRIORITY_MAP.find { |key, _| basename.include?(key) }&.last || 10
      end
    end

    def signature_line?(stripped)
      stripped.match?(/\A\s*(def\s|attr_|include\s|extend\s|has_|belongs_|validates|scope\s|delegate\s)/)
    end

    def class_or_module_line?(stripped)
      stripped.match?(/\A\s*(class|module)\s/)
    end

    def block_opener?(stripped)
      stripped.match?(/\Adef\s/)
    end

    def current_indent(line)
      line.match(/\A(\s*)/)[1].length
    end

    def safe_read(path)
      absolute = absolute_path(path)
      Tools::WorkspaceIo.read_file(absolute)
    rescue StandardError
      nil
    end

    def safe_exists?(path)
      Tools::WorkspaceIo.file_exists?(absolute_path(path))
    rescue StandardError
      false
    end

    def absolute_path(path)
      path.start_with?("/") ? path : File.join(Tools::FileReadExecutor::WORKSPACE_ROOT, path)
    end

    def estimate_tokens(text)
      (text.bytesize.to_f / CHARS_PER_TOKEN).ceil
    end
  end
end
